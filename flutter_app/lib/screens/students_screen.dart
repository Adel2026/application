import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_locale.dart';
import '../core/cloud_sync_service.dart';
import '../core/contact_picker_service.dart';
import '../core/database/database_service.dart';
import '../core/security_service.dart';
import '../core/whatsapp_service.dart';
import '../core/report_dispatch_helper.dart';
import '../models/attendance_model.dart';
import '../models/curriculum_model.dart';
import '../models/group_model.dart';
import '../models/payment_model.dart';
import '../models/student_model.dart';
import '../widgets/section_top_bar.dart';
import 'reports_screen.dart';
import 'teacher_student_app_control_screen.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key, required this.database, this.onBack});
  final DatabaseService database;
  final VoidCallback? onBack;

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  String searchQuery = '';
  String? selectedGroupId;
  String activeFilter = 'all'; // 'all', 'debts', 'paid'
  List<StudentModel> allStudents = [];
  List<GroupModel> groups = [];
  bool isLoading = true;
  StreamSubscription<DataChangeEvent>? _dataSub;
  Timer? _searchDebounce;
  late final TextEditingController _searchController;

  // Batch Multi-Select Mode
  bool isSelectionMode = false;
  final Set<String> selectedStudentIds = {};

  void _toggleSelection(String studentId) {
    HapticFeedback.lightImpact();
    setState(() {
      if (selectedStudentIds.contains(studentId)) {
        selectedStudentIds.remove(studentId);
        if (selectedStudentIds.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedStudentIds.add(studentId);
      }
    });
  }

  void _selectAllCurrent() {
    HapticFeedback.lightImpact();
    final currentIds = filteredStudents.map((s) => s.id).toSet();
    final allSelected =
        currentIds.isNotEmpty &&
        currentIds.every((id) => selectedStudentIds.contains(id));
    setState(() {
      if (allSelected) {
        selectedStudentIds.removeAll(currentIds);
        if (selectedStudentIds.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedStudentIds.addAll(currentIds);
        isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    HapticFeedback.lightImpact();
    setState(() {
      isSelectionMode = false;
      selectedStudentIds.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _loadData(reloadGroups: true);
    _dataSub = widget.database.onDataChanged.listen((event) {
      if (event == DataChangeEvent.students ||
          event == DataChangeEvent.groups ||
          event == DataChangeEvent.all) {
        if (mounted) {
          _loadData(
            reloadGroups: event == DataChangeEvent.groups || event == DataChangeEvent.all,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _dataSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    searchQuery = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _loadData(isSearch: true);
      }
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      searchQuery = '';
      selectedGroupId = null;
    });
    _loadData();
  }

  Future<void> _loadData({bool isSearch = false, bool reloadGroups = false}) async {
    if (!isSearch && allStudents.isEmpty) {
      setState(() => isLoading = true);
    }
    final Future<List<GroupModel>> groupsFuture = (reloadGroups || groups.isEmpty)
        ? widget.database.getGroups()
        : Future.value(groups);

    final results = await Future.wait([
      groupsFuture,
      widget.database.getStudents(
        groupId: selectedGroupId,
        searchQuery: searchQuery,
      ),
    ]);

    if (mounted) {
      setState(() {
        groups = results[0] as List<GroupModel>;
        allStudents = results[1] as List<StudentModel>;
        isLoading = false;
      });
    }
  }

  List<StudentModel> get filteredStudents {
    final query = searchQuery.trim().toLowerCase();
    return allStudents.where((s) {
      if (activeFilter == 'debts' && !s.hasOutstandingPayment) return false;
      if (activeFilter == 'paid' && s.hasOutstandingPayment) return false;
      if (selectedGroupId != null && s.groupId != selectedGroupId) return false;

      if (query.isNotEmpty) {
        final nameMatch = s.fullName.toLowerCase().contains(query);
        final codeMatch = s.id.toLowerCase().contains(query);
        final phoneMatch = s.studentPhone.contains(query) || s.parentPhone.contains(query);
        final parentNameMatch = s.parentName.toLowerCase().contains(query);
        final gradeMatch = s.grade.toLowerCase().contains(query) || s.stage.toLowerCase().contains(query);

        final group = groups.where((g) => g.id == s.groupId).firstOrNull;
        final groupMatch = group != null && group.name.toLowerCase().contains(query);

        if (!nameMatch && !codeMatch && !phoneMatch && !parentNameMatch && !gradeMatch && !groupMatch) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  double get totalDebts {
    return allStudents.fold(0.0, (sum, s) => sum + s.outstandingAmount);
  }

  int get debtorsCount {
    return allStudents.where((s) => s.hasOutstandingPayment).length;
  }

  Future<void> _showAddOrEditStudentDialog({
    StudentModel? existingStudent,
  }) async {
    final formKey = GlobalKey<FormState>();
    final isEditing = existingStudent != null;
    final initialCode =
        existingStudent?.id ?? await widget.database.getNextStudentCode();
    final codeCtrl = TextEditingController(text: initialCode);
    final nameCtrl = TextEditingController(
      text: existingStudent?.fullName ?? '',
    );
    final studentPhoneCtrl = TextEditingController(
      text: existingStudent?.studentPhone ?? '',
    );
    final parentNameCtrl = TextEditingController(
      text: existingStudent?.parentName ?? '',
    );
    final parentPhoneCtrl = TextEditingController(
      text: existingStudent?.parentPhone ?? '',
    );

    // Grade options matching curriculum system
    final List<String> allGrades = [
      'الصف الرابع الابتدائي (Pri 4)',
      'الصف الخامس الابتدائي (Pri 5)',
      'الصف السادس الابتدائي (Pri 6)',
      'الصف الأول الإعدادي (Prep 1)',
      'الصف الثاني الإعدادي (Prep 2)',
      'الصف الثالث الإعدادي (Prep 3)',
      'الصف الأول الثانوي (Sec 1)',
      'الصف الثاني الثانوي (Sec 2)',
      'الصف الثالث الثانوي (Sec 3)',
      'كورس حر / تعليم مستمر',
    ];

    // Assigned group
    String? assignedGroupId = existingStudent?.groupId;
    if (assignedGroupId != null &&
        !groups.any((g) => g.id == assignedGroupId)) {
      assignedGroupId = null;
    }
    if (assignedGroupId == null && groups.isNotEmpty && !isEditing) {
      assignedGroupId = groups.first.id;
    }

    String selectedGrade = existingStudent?.grade ?? '';
    if (selectedGrade.isEmpty || !allGrades.contains(selectedGrade)) {
      if (assignedGroupId != null) {
        final g = groups.firstWhere(
          (grp) => grp.id == assignedGroupId,
          orElse: () => groups.first,
        );
        if (g.grade.isNotEmpty && allGrades.contains(g.grade)) {
          selectedGrade = g.grade;
        } else {
          selectedGrade = allGrades.first;
        }
      } else {
        selectedGrade = allGrades.first;
      }
    }

    bool isActive = existingStudent?.isActive ?? true;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            // Find current selected group
            GroupModel? currentGroup;
            if (assignedGroupId != null) {
              try {
                currentGroup = groups.firstWhere(
                  (g) => g.id == assignedGroupId,
                );
              } catch (_) {}
            }

            final savedGroupSubject = currentGroup?.subject ?? '';
            final groupSubject = savedGroupSubject.contains('تكنولوجيا')
              ? 'ICT'
              : savedGroupSubject.isNotEmpty
              ? savedGroupSubject
              : (selectedGrade.contains('ثانوي') ||
                    selectedGrade.contains('Sec')
                  ? 'برمجة'
                  : 'ICT');

            String gradeSummary = '1 ثانوي و 2 ثانوي';
            if (selectedGrade.contains('Sec 1') ||
                selectedGrade.contains('الأول الثانوي')) {
              gradeSummary = '1 ثانوي و 2 ثانوي';
            } else if (selectedGrade.contains('Sec 2') ||
                selectedGrade.contains('الثاني الثانوي')) {
              gradeSummary = '2 ثانوي و 3 ثانوي';
            } else if (selectedGrade.contains('Sec 3') ||
                selectedGrade.contains('الثالث الثانوي')) {
              gradeSummary = '3 ثانوي';
            } else if (selectedGrade.contains('Prep') ||
                selectedGrade.contains('الإعدادي')) {
              gradeSummary = 'المرحلة الإعدادية';
            } else if (selectedGrade.contains('Pri') ||
                selectedGrade.contains('الابتدائي')) {
              gradeSummary = 'المرحلة الابتدائية';
            } else {
              gradeSummary = 'عام';
            }

            return Directionality(
              textDirection: AppLocale.isArabic(context)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: 520,
                    maxHeight: MediaQuery.of(ctx).size.height * 0.90,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141D2B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF26354D),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- 1. Pinned Header Bar ---
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Color(0xFF1E2B3E),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Right side (RTL Start): Green Avatar + Title
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F3229),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF135E49),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.person_outline_rounded,
                                color: Color(0xFF10B981),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isEditing ? 'تعديل طالب' : 'إضافة طالب',
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            // Left side (RTL End): Close 'X' icon button
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF94A3B8),
                                size: 22,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),

                      // --- 2. Scrollable Form Body ---
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Form(
                            key: formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 0. حالة الطالب (نشط / متوقف)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  decoration: BoxDecoration(
                                    color: (isActive ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: (isActive ? Colors.green : Colors.orange).withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: SwitchListTile(
                                    value: isActive,
                                    onChanged: (val) => setModalState(() => isActive = val),
                                    activeThumbColor: Colors.green,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                    title: Text(
                                      isActive ? 'حالة الطالب: نشط 🟢' : 'حالة الطالب: متوقف مؤقتاً ⏸️',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: isActive ? Colors.green.shade400 : Colors.orange.shade400,
                                      ),
                                    ),
                                    subtitle: Text(
                                      isActive ? 'الطالب نشط ومتاح في كشوف الحضور ومتابعة الحصص' : 'الطالب متوقف مؤقتاً ومحفوظ دون حذف سجلاته',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    ),
                                  ),
                                ),

                                // 0. كود الطالب (ID)
                                Row(
                                  children: [
                                    const Text(
                                      'كود الطالب (ID)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      '*',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: const Text(
                                        'كود عشوائي (5 أرقام)',
                                        style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: codeCtrl,
                                  keyboardType: TextInputType.number,
                                  maxLength: 5,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '48291',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 13,
                                    ),
                                    counterStyle: const TextStyle(color: Colors.grey, fontSize: 10),
                                    prefixIcon: const Icon(
                                      Icons.badge_rounded,
                                      color: Color(0xFF10B981),
                                      size: 18,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: 'توليد كود عشوائي جديد 🎲',
                                      icon: const Icon(
                                        Icons.casino_rounded,
                                        color: Color(0xFF10B981),
                                        size: 20,
                                      ),
                                      onPressed: () async {
                                        final r = await widget.database.generateUniqueRandom5DigitCode();
                                        codeCtrl.text = r;
                                      },
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF0E1522),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF10B981),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'برجاء إدخال كود الطالب';
                                    }
                                    final clean = v.trim().replaceAll(RegExp(r'\D'), '');
                                    if (clean.length != 5) {
                                      return 'يجب أن يتكون كود الطالب من 5 أرقام بالضبط (مثال: 10001)';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),

                                // 1. اسم الطالب الكامل *
                                Row(
                                  children: const [
                                    Text(
                                      'اسم الطالب',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      '*',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: nameCtrl,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'مثال: عمر أحمد الشناوي',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 13,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF0E1522),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF10B981),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'برجاء كتابة اسم الطالب'
                                      : null,
                                ),
                                const SizedBox(height: 14),

                                // 2. هاتف الطالب (واتساب)
                                const Text(
                                  'هاتف الطالب',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: studentPhoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '010XXXXXXXX',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 13,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.phone_iphone_rounded,
                                      color: Color(0xFF64748B),
                                      size: 18,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: const Icon(
                                        Icons.contacts_rounded,
                                        color: Color(0xFF10B981),
                                        size: 20,
                                      ),
                                      tooltip: 'اختيار من دليل الهاتف',
                                      onPressed: () async {
                                        HapticFeedback.lightImpact();
                                        final contact =
                                            await ContactPickerService.pickContact();
                                        if (contact != null &&
                                            contact.phone.isNotEmpty) {
                                          studentPhoneCtrl.text = contact.phone;
                                          if (nameCtrl.text.trim().isEmpty &&
                                              contact.name.isNotEmpty) {
                                            nameCtrl.text = contact.name;
                                          }
                                        }
                                      },
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF0E1522),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF10B981),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // 3. اسم ولي الأمر
                                const Text(
                                  'اسم ولي الأمر',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: parentNameCtrl,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'مثال: أحمد الشناوي',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 13,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF0E1522),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF10B981),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // 4. هاتف ولي الأمر *
                                Row(
                                  children: const [
                                    Text(
                                      'هاتف ولي الأمر',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      '*',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: parentPhoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '01XXXXXXXXX',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 13,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.contact_phone_rounded,
                                      color: Color(0xFF64748B),
                                      size: 18,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: const Icon(
                                        Icons.contacts_rounded,
                                        color: Color(0xFF10B981),
                                        size: 20,
                                      ),
                                      tooltip: 'اختيار من دليل الهاتف',
                                      onPressed: () async {
                                        HapticFeedback.lightImpact();
                                        final contact =
                                            await ContactPickerService.pickContact();
                                        if (contact != null &&
                                            contact.phone.isNotEmpty) {
                                          parentPhoneCtrl.text = contact.phone;
                                          if (parentNameCtrl.text
                                                  .trim()
                                                  .isEmpty &&
                                              contact.name.isNotEmpty) {
                                            parentNameCtrl.text = contact.name;
                                          }
                                        }
                                      },
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF0E1522),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF223046),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF10B981),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'برجاء كتابة هاتف ولي الأمر للمتابعة'
                                      : null,
                                ),
                                const SizedBox(height: 14),

                                // 5. المجموعة الدراسية *
                                Row(
                                  children: [
                                    const Text(
                                      'المجموعة',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      '*',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Text(
                                      'تحديد المادة',
                                      style: TextStyle(
                                        color: Color(0xFF38BDF8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0E1522),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFF223046),
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String?>(
                                      value: assignedGroupId,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF16233B),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Color(0xFF94A3B8),
                                        size: 22,
                                      ),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text(
                                            'بدون مجموعة (طالب مستقل)',
                                            style: TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        ...groups.map((g) {
                                          final gradeLabel = g.grade.isNotEmpty
                                              ? g.grade
                                              : g.stage;
                                          return DropdownMenuItem<String?>(
                                            value: g.id,
                                            child: Text(
                                              '${g.name} — ($gradeLabel)',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }),
                                      ],
                                      onChanged: (v) {
                                        setModalState(() {
                                          assignedGroupId = v;
                                          if (v != null) {
                                            final grp = groups.firstWhere(
                                              (g) => g.id == v,
                                              orElse: () => groups.first,
                                            );
                                            if (grp.grade.isNotEmpty &&
                                                allGrades.contains(grp.grade)) {
                                              selectedGrade = grp.grade;
                                            }
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // 6. المرحلة / الصف الدراسي *
                                Row(
                                  children: [
                                    const Text(
                                      'الصف الدراسي',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      '*',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Text(
                                      'حسب المجموعة',
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0E1522),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFF223046),
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: allGrades.contains(selectedGrade)
                                          ? selectedGrade
                                          : allGrades.first,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF16233B),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Color(0xFF94A3B8),
                                        size: 22,
                                      ),
                                      items: allGrades.map((g) {
                                        return DropdownMenuItem(
                                          value: g,
                                          child: Text(
                                            g,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (v) {
                                        if (v != null)
                                          setModalState(
                                            () => selectedGrade = v,
                                          );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // 7. Information Card: المادة المرتبطة بالمرحلة
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF061A1D),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFF0E473F),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.school_rounded,
                                        color: Color(0xFF10B981),
                                        size: 19,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'المادة: $groupSubject ($gradeSummary)',
                                          style: const TextStyle(
                                            color: Color(0xFF34D399),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0B2E24),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFF135E49),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          'المجموعة: $groupSubject',
                                          style: const TextStyle(
                                            color: Color(0xFF10B981),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // --- 3. Divider Line Above Actions ---
                      Container(height: 1, color: const Color(0xFF1E2B3E)),

                      // --- 4. Pinned Bottom Actions Bar ---
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            // Spacer pushes buttons to the left in RTL
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                              child: const Text(
                                'إلغاء',
                                style: TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                if (formKey.currentState?.validate() ?? false) {
                                  String stage = 'الثانوية العامة';
                                  if (selectedGrade.contains('الثانوي') ||
                                      selectedGrade.contains('Sec')) {
                                    stage = 'الثانوية العامة';
                                  } else if (selectedGrade.contains(
                                        'الإعدادي',
                                      ) ||
                                      selectedGrade.contains('Prep')) {
                                    stage = 'المرحلة الإعدادية';
                                  } else if (selectedGrade.contains(
                                        'الابتدائي',
                                      ) ||
                                      selectedGrade.contains('Pri')) {
                                    stage = 'المرحلة الابتدائية';
                                  } else {
                                    stage = 'عام';
                                  }

                                  final studentId =
                                      codeCtrl.text.trim().isNotEmpty
                                      ? codeCtrl.text.trim()
                                      : (existingStudent?.id ??
                                            await widget.database
                                                .getNextStudentCode());

                                  if (isEditing && existingStudent.id != studentId) {
                                    await widget.database.updateStudentIdCascade(existingStudent.id, studentId);
                                    try {
                                      final col = FirebaseFirestore.instance
                                          .collection('academies')
                                          .doc('default')
                                          .collection('students');
                                      final oldDoc = await col.doc(existingStudent.id).get();
                                      if (oldDoc.exists && oldDoc.data() != null) {
                                        final data = Map<String, dynamic>.from(oldDoc.data()!);
                                        data['id'] = studentId;
                                        data['student_code'] = studentId;
                                        data['updated_at'] = FieldValue.serverTimestamp();
                                        await col.doc(studentId).set(data, SetOptions(merge: true));
                                        await col.doc(existingStudent.id).delete();
                                      }
                                      await CloudSyncService.instance.syncStudents();
                                    } catch (_) {}
                                  }

                                  final student = StudentModel(
                                    id: studentId,
                                    fullName: nameCtrl.text.trim(),
                                    stage: stage,
                                    grade: selectedGrade,
                                    studentPhone: studentPhoneCtrl.text.trim(),
                                    parentPhone: parentPhoneCtrl.text.trim(),
                                    groupId: assignedGroupId,
                                    paymentPlan:
                                        existingStudent?.paymentPlan ?? 'شهري',
                                    outstandingAmount:
                                        existingStudent?.outstandingAmount ?? 0,
                                    parentName: parentNameCtrl.text.trim(),
                                    isActive: isActive,
                                  );

                                  await widget.database.saveStudent(student);

                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  if (!mounted) return;

                                  await _loadData();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          isEditing
                                              ? 'تم تعديل بيانات (${student.fullName}) بنجاح ✅'
                                              : 'تمت إضافة الطالب (${student.fullName}) بنجاح ✅',
                                        ),
                                        backgroundColor: const Color(0xFF10B981),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                isEditing ? 'حفظ' : 'إضافة',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  void _showStudentDetail(StudentModel student) async {
    final shouldEdit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StudentDetailSheet(
        student: student,
        database: widget.database,
        groups: groups,
        onEdit: () {
          Navigator.pop(ctx, true);
        },
        onDeleted: () {
          Navigator.pop(ctx, false);
          _loadData();
        },
        onPaymentRecorded: () {
          _loadData();
        },
      ),
    );

    if (shouldEdit == true && mounted) {
      _showAddOrEditStudentDialog(existingStudent: student);
    }
  }

  void _showPaymentDialog(StudentModel student) {
    final amountCtrl = TextEditingController(
      text: student.outstandingAmount > 0
          ? student.outstandingAmount.toStringAsFixed(0)
          : '200',
    );
    final noteCtrl = TextEditingController();
    String paymentType = 'اشتراك شهري';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.payment, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تحصيل من: ${student.fullName}',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'المبلغ المدفوع (ج.م)',
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: paymentType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'نوع التحصيل'),
                items: const [
                  DropdownMenuItem(
                    value: 'اشتراك شهري',
                    child: Text('اشتراك شهري', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'حصة فردية',
                    child: Text('حصة فردية', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'مذكرة / كتب',
                    child: Text('مذكرة / كتب', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'رسوم امتحان',
                    child: Text('رسوم امتحان', overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) paymentType = v;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            icon: const Icon(Icons.check),
            label: const Text('تأكيد التحصيل'),
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (amount > 0) {
                final payment = PaymentModel(
                  studentId: student.id,
                  amount: amount,
                  date: DateTime.now().toIso8601String().substring(0, 10),
                  type: paymentType,
                  note: noteCtrl.text.trim(),
                );
                await widget.database.recordPayment(payment);
                final sent = await WhatsAppService.autoSendPaymentReceipt(
                  database: widget.database,
                  studentName: student.fullName,
                  parentPhone: student.parentPhone,
                  amount: amount,
                  type: paymentType,
                  date: payment.date,
                );

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green,
                    content: Text(
                      sent
                          ? 'تم تسجيل الدفعة وإرسال إيصال واتساب لولي الأمر تلقائياً 📲'
                          : 'تم تسجيل الدفعة بنجاح واستنزالها من المتأخرات',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }


  Future<void> _showBatchChangeGroupDialog() async {
    if (selectedStudentIds.isEmpty) return;
    String? chosenGroupId = groups.isNotEmpty ? groups.first.id : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Directionality(
              textDirection: AppLocale.isArabic(ctx)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: AlertDialog(
                backgroundColor: isDark
                    ? const Color(0xFF0F172A)
                    : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.group_add_rounded,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'نقل ${selectedStudentIds.length} طالب إلى مجموعة',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'اختر المجموعة الجديدة لتسكين الطلاب المحددين فيها:',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: chosenGroupId,
                          isExpanded: true,
                          dropdownColor: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'بدون مجموعة (إلغاء التسكين)',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                            ...groups.map((g) {
                              final gradeLabel = g.grade.isNotEmpty
                                  ? g.grade
                                  : g.stage;
                              return DropdownMenuItem<String?>(
                                value: g.id,
                                child: Text(
                                  '${g.name} ($gradeLabel)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setModalState(() => chosenGroupId = val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('تأكيد النقل'),
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      final count = selectedStudentIds.length;
      await widget.database.updateStudentsGroupBatch(
        selectedStudentIds.toList(),
        chosenGroupId,
      );
      _exitSelectionMode();
      await _loadData();
      if (mounted) {
        final groupName =
            groups.where((g) => g.id == chosenGroupId).firstOrNull?.name ??
            'بدون مجموعة';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Text('تم نقل $count طالب إلى "$groupName" بنجاح ✅'),
          ),
        );
      }
    }
  }

  Future<void> _showBatchDeleteDialog() async {
    if (selectedStudentIds.isEmpty) return;
    final count = selectedStudentIds.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Directionality(
          textDirection: AppLocale.isArabic(ctx)
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.delete_sweep_rounded,
                    color: Colors.redAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'حذف $count طالب',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'هل أنت متأكد من حذف $count طالب دفعة واحدة؟',
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تنبيه: سيتم حذف جميع بيانات الحضور والغياب والدرجات والمدفوعات المرتبطة بهؤلاء الطلاب نهائياً.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text('تأكيد الحذف النهائي'),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      await widget.database.deleteStudentsBatch(selectedStudentIds.toList());
      _exitSelectionMode();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            content: Text('تم حذف $count طالب نهائياً 🗑️'),
          ),
        );
      }
    }
  }

  Future<void> _showBatchEditDialog() async {
    if (selectedStudentIds.isEmpty) return;
    final count = selectedStudentIds.length;

    bool updateGrade = false;
    String selectedGrade = 'الصف الأول الثانوي (Sec 1)';

    bool updatePlan = false;
    String selectedPlan = 'شهري';

    bool resetDebts = false;

    final allGrades = [
      'الصف الرابع الابتدائي (Pri 4)',
      'الصف الخامس الابتدائي (Pri 5)',
      'الصف السادس الابتدائي (Pri 6)',
      'الصف الأول الإعدادي (Prep 1)',
      'الصف الثاني الإعدادي (Prep 2)',
      'الصف الثالث الإعدادي (Prep 3)',
      'الصف الأول الثانوي (Sec 1)',
      'الصف الثاني الثانوي (Sec 2)',
      'الصف الثالث الثانوي (Sec 3)',
      'كورس حر / تعليم مستمر',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Directionality(
              textDirection: AppLocale.isArabic(ctx)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: AlertDialog(
                backgroundColor: isDark
                    ? const Color(0xFF0F172A)
                    : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.edit_note_rounded,
                        color: Color(0xFF38BDF8),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'تعديل جماعي لـ $count طالب',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'اختر الحقول التي ترغب في تطبيقها وتحديثها للطلاب المحددين:',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),

                      // 1. Grade update
                      CheckboxListTile(
                        value: updateGrade,
                        title: const Text(
                          'تغيير الصف الدراسي',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: updateGrade
                            ? Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF38BDF8),
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: selectedGrade,
                                      isExpanded: true,
                                      dropdownColor: isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.white,
                                      items: allGrades
                                          .map(
                                            (g) => DropdownMenuItem(
                                              value: g,
                                              child: Text(
                                                g,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null)
                                          setModalState(
                                            () => selectedGrade = v,
                                          );
                                      },
                                    ),
                                  ),
                                ),
                              )
                            : null,
                        onChanged: (val) =>
                            setModalState(() => updateGrade = val ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Divider(height: 16),

                      // 2. Payment Plan update
                      CheckboxListTile(
                        value: updatePlan,
                        title: const Text(
                          'تغيير نظام / خطة الدفع',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: updatePlan
                            ? Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF10B981),
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: selectedPlan,
                                      isExpanded: true,
                                      dropdownColor: isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.white,
                                      items:
                                          [
                                                'شهري',
                                                'بالحصة',
                                                'ترم كامل',
                                                'مجاني / منحة',
                                              ]
                                              .map(
                                                (p) => DropdownMenuItem(
                                                  value: p,
                                                  child: Text(
                                                    p,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (v) {
                                        if (v != null)
                                          setModalState(() => selectedPlan = v);
                                      },
                                    ),
                                  ),
                                ),
                              )
                            : null,
                        onChanged: (val) =>
                            setModalState(() => updatePlan = val ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Divider(height: 16),

                      // 3. Reset debts
                      CheckboxListTile(
                        value: resetDebts,
                        title: const Text(
                          'تصفير المتأخرات المالية (0 ج)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'تحديد رصيد المتأخرات للطلاب المحددين ليكون خالص السداد بالكامل.',
                          style: TextStyle(fontSize: 11),
                        ),
                        onChanged: (val) =>
                            setModalState(() => resetDebts = val ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('تطبيق التعديلات'),
                    onPressed: (!updateGrade && !updatePlan && !resetDebts)
                        ? null
                        : () => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      String? gradeVal = updateGrade ? selectedGrade : null;
      String? stageVal;
      if (gradeVal != null) {
        if (gradeVal.contains('الثانوي') || gradeVal.contains('Sec')) {
          stageVal = 'الثانوية العامة';
        } else if (gradeVal.contains('الإعدادي') || gradeVal.contains('Prep')) {
          stageVal = 'المرحلة الإعدادية';
        } else if (gradeVal.contains('الابتدائي') || gradeVal.contains('Pri')) {
          stageVal = 'المرحلة الابتدائية';
        } else {
          stageVal = 'عام';
        }
      }

      await widget.database.updateStudentsBatchFields(
        selectedStudentIds.toList(),
        grade: gradeVal,
        stage: stageVal,
        paymentPlan: updatePlan ? selectedPlan : null,
        outstandingAmount: resetDebts ? 0.0 : null,
      );

      _exitSelectionMode();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Text('تم تحديث بيانات $count طالب بنجاح ✅'),
          ),
        );
      }
    }
  }

  Widget _buildBatchActionBar(BuildContext context, bool isDark) {
    final count = selectedStudentIds.length;
    final currentList = filteredStudents;
    final bool allCurrentlySelected =
        currentList.isNotEmpty &&
        currentList.every((s) => selectedStudentIds.contains(s.id));

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'تم تحديد $count طالب',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(
                  allCurrentlySelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  size: 17,
                ),
                label: Text(
                  allCurrentlySelected
                      ? 'إلغاء تحديد الكل'
                      : 'تحديد الكل (${currentList.length})',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: _selectAllCurrent,
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'إلغاء التحديد',
                onPressed: _exitSelectionMode,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Change Group
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.group_add_rounded, size: 17),
                  label: const Text(
                    'المجموعة',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _showBatchChangeGroupDialog,
                ),
              ),
              const SizedBox(width: 8),

              // Batch Edit
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text(
                    'تعديل',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _showBatchEditDialog,
                ),
              ),
              const SizedBox(width: 8),

              // Batch Delete
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: const Text(
                    'حذف',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _showBatchDeleteDialog,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentList = filteredStudents;

    return PopScope(
      canPop: !isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: SectionTopBar(
          title: 'الطلاب',
          icon: Icons.people_rounded,
          onBack: widget.onBack,
          actionLabel: 'إضافة طالب',
          actionIcon: Icons.person_add_rounded,
          onAction: () => _showAddOrEditStudentDialog(),
        ),
        bottomNavigationBar: (isSelectionMode && selectedStudentIds.isNotEmpty)
            ? _buildBatchActionBar(context, isDark)
            : null,
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // 1. أولاً: الإحصائيات (Summary KPI Ribbon First)
                  _buildStatsHeader(isDark),

                  // 2. تحتيها: تقسيم الطلاب بحجم أصغر في العرض (Compact Student Segmentation)
                  _buildCompactSegmentationBar(isDark),

                  // 3. وتحتها: مربع البحث الذكي مع سهم القائمة الذكية والتقارير (Smart Search Bar)
                  _buildSmartSearchBar(isDark),

                  // 4. قائمة الطلاب
                  Expanded(
                    child: currentList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_off_outlined,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  searchQuery.isNotEmpty
                                      ? 'لا توجد نتائج مطابقة للبحث'
                                      : 'لم يتم تسجيل أي طلاب بعد',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('إضافة أول طالب الآن'),
                                  onPressed: () =>
                                      _showAddOrEditStudentDialog(),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            key: const PageStorageKey<String>('students_screen_list_view'),
                            padding: EdgeInsets.fromLTRB(
                              16,
                              8,
                              16,
                              (isSelectionMode && selectedStudentIds.isNotEmpty)
                                  ? 120
                                  : 36,
                            ),
                            itemCount: currentList.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (ctx, i) {
                              final student = currentList[i];
                              final isSelected = selectedStudentIds.contains(
                                student.id,
                              );
                              final group = groups
                                  .where((g) => g.id == student.groupId)
                                  .firstOrNull;
                              final hasDebt = student.hasOutstandingPayment;

                              return Card(
                                key: ValueKey('student_card_${student.id}'),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: BorderSide(
                                    color: isSelected
                                        ? const Color(0xFF10B981)
                                        : (hasDebt
                                              ? (isDark
                                                    ? const Color(0xFF7F1D1D)
                                                    : const Color(0xFFFECACA))
                                              : (isDark
                                                    ? const Color(0xFF334155)
                                                    : const Color(0xFFE2E8F0))),
                                    width: isSelected ? 1.8 : 1,
                                  ),
                                ),
                                color: isSelected
                                    ? (isDark
                                          ? const Color(0xFF0F2E24)
                                          : const Color(0xFFF0FDF4))
                                    : (isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.white),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () {
                                    if (isSelectionMode) {
                                      _toggleSelection(student.id);
                                    } else {
                                      _showStudentDetail(student);
                                    }
                                  },
                                  onLongPress: () {
                                    HapticFeedback.mediumImpact();
                                    if (!isSelectionMode) {
                                      setState(() {
                                        isSelectionMode = true;
                                        selectedStudentIds.add(student.id);
                                      });
                                    } else {
                                      _toggleSelection(student.id);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        // Checkbox in selection mode
                                        AnimatedSize(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          curve: Curves.easeInOut,
                                          child: isSelectionMode
                                              ? Padding(
                                                  padding:
                                                      const EdgeInsetsDirectional.only(
                                                        end: 10,
                                                      ),
                                                  child: SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child: Checkbox(
                                                      value: isSelected,
                                                      activeColor: const Color(
                                                        0xFF10B981,
                                                      ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      onChanged: (_) =>
                                                          _toggleSelection(
                                                            student.id,
                                                          ),
                                                    ),
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),

                                        // Squircle Avatar
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: hasDebt
                                                ? (isDark
                                                      ? Colors.red.withValues(
                                                          alpha: 0.2,
                                                        )
                                                      : const Color(0xFFFEE2E2))
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(
                                                        alpha: isDark
                                                            ? 0.2
                                                            : 0.1,
                                                      ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: hasDebt
                                                  ? const Color(0xFFF87171)
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                              width: 1,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              student.fullName.isNotEmpty
                                                  ? student
                                                        .fullName
                                                        .characters
                                                        .first
                                                  : 'ط',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: hasDebt
                                                    ? const Color(0xFFEF4444)
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // Student Information
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                AppLocale.localizeData(
                                                  context,
                                                  student.fullName,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: -0.2,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 5),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isDark
                                                          ? const Color(
                                                              0xFF0F172A,
                                                            )
                                                          : const Color(
                                                              0xFFF1F5F9,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: isDark
                                                            ? const Color(
                                                                0xFF334155,
                                                              )
                                                            : const Color(
                                                                0xFFE2E8F0,
                                                              ),
                                                        width: 0.6,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      AppLocale.localizeData(
                                                        context,
                                                        group?.name ??
                                                            (AppLocale.isArabic(
                                                                  context,
                                                                )
                                                                ? 'بدون مجموعة'
                                                                : 'No Group'),
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: isDark
                                                            ? const Color(
                                                                0xFF94A3B8,
                                                              )
                                                            : const Color(
                                                                0xFF475569,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    AppLocale.localizeData(
                                                      context,
                                                      student.grade,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isDark
                                                          ? const Color(
                                                              0xFF64748B,
                                                            )
                                                          : const Color(
                                                              0xFF94A3B8,
                                                            ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: student.isActive
                                                          ? Colors.green.withValues(alpha: 0.12)
                                                          : Colors.amber.withValues(alpha: 0.15),
                                                      borderRadius:
                                                          BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: student.isActive
                                                            ? Colors.green.withValues(alpha: 0.4)
                                                            : Colors.amber.shade700,
                                                        width: 0.6,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      student.isActive
                                                          ? (AppLocale.isArabic(context) ? 'نشط 🟢' : 'Active 🟢')
                                                          : (AppLocale.isArabic(context) ? 'متوقف ⏸️' : 'Paused ⏸️'),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: student.isActive
                                                            ? Colors.green
                                                            : Colors.amber.shade800,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),

                                              // Status Badges
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: hasDebt
                                                          ? (isDark
                                                                ? Colors
                                                                      .red
                                                                      .shade900
                                                                      .withValues(
                                                                        alpha:
                                                                            0.35,
                                                                      )
                                                                : const Color(
                                                                    0xFFFEF2F2,
                                                                  ))
                                                          : (isDark
                                                                ? Colors
                                                                      .green
                                                                      .shade900
                                                                      .withValues(
                                                                        alpha:
                                                                            0.35,
                                                                      )
                                                                : const Color(
                                                                    0xFFF0FDF4,
                                                                  )),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      border: Border.all(
                                                        color: hasDebt
                                                            ? (isDark
                                                                  ? Colors
                                                                        .red
                                                                        .shade800
                                                                  : const Color(
                                                                      0xFFFECACA,
                                                                    ))
                                                            : (isDark
                                                                  ? Colors
                                                                        .green
                                                                        .shade800
                                                                  : const Color(
                                                                      0xFFBBF7D0,
                                                                    )),
                                                        width: 0.6,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      hasDebt
                                                          ? '${AppLocale.tr(context, 'debt', ar: 'متأخرات', en: 'Due')}: ${student.outstandingAmount.toStringAsFixed(0)} ${AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP')}'
                                                          : AppLocale.tr(
                                                              context,
                                                              'all_paid',
                                                              ar: 'خالص السداد ✅',
                                                              en: 'Fully Paid ✅',
                                                            ),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: hasDebt
                                                            ? const Color(
                                                                0xFFEF4444,
                                                              )
                                                            : const Color(
                                                                0xFF10B981,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isDark
                                                          ? const Color(
                                                              0xFF0F172A,
                                                            )
                                                          : const Color(
                                                              0xFFF8FAFC,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      AppLocale.localizeData(
                                                        context,
                                                        student.paymentPlan,
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: isDark
                                                            ? const Color(
                                                                0xFF94A3B8,
                                                              )
                                                            : const Color(
                                                                0xFF64748B,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Trailing Quick Action Buttons
                                        if (!isSelectionMode)
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              IconButton(
                                                style: IconButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFF25D366,
                                                  ).withValues(alpha: 0.12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  padding: const EdgeInsets.all(
                                                    7,
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons
                                                      .chat_bubble_outline_rounded,
                                                  color: Color(0xFF25D366),
                                                  size: 19,
                                                ),
                                                tooltip: 'واتساب ولي الأمر',
                                                onPressed: () {
                                                  WhatsAppService.openWhatsApp(
                                                    phone: student.parentPhone,
                                                    message:
                                                        'السلام عليكم ورحمة الله، بخصوص الطالب ${student.fullName}.',
                                                  );
                                                },
                                              ),
                                              const SizedBox(height: 6),
                                              IconButton(
                                                style: IconButton.styleFrom(
                                                  backgroundColor: Colors.blue
                                                      .withValues(alpha: 0.12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  padding: const EdgeInsets.all(
                                                    7,
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.payment_rounded,
                                                  color: Colors.blue,
                                                  size: 19,
                                                ),
                                                tooltip: 'تسجيل تحصيل فوري',
                                                onPressed: () =>
                                                    _showPaymentDialog(student),
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
              ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // 1. أولاً: هيدر الإحصائيات (Summary KPI Ribbon First)
  // ---------------------------------------------------------------------------
  Widget _buildStatsHeader(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatText(
              label: 'إجمالي الطلاب',
              value: '${allStudents.length} طالب',
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          Expanded(
            child: _StatText(
              label: 'إجمالي المتأخرات',
              value: '${totalDebts.toStringAsFixed(0)} ج.م',
              color: totalDebts > 0
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          Expanded(
            child: _StatText(
              label: 'المجموعات النشطة',
              value: '${groups.length} مجموعات',
            ),
          ),
        ],
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // 2. تحتيها: تقسيم الطلاب بحجم أصغر في العرض (Compact Student Segmentation Bar)
  // ---------------------------------------------------------------------------
  Widget _buildCompactSegmentationBar(bool isDark) {
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _buildCompactFilterPill(
            label: 'الكل (${allStudents.length})',
            isSelected: activeFilter == 'all' && selectedGroupId == null,
            onTap: () {
              setState(() {
                activeFilter = 'all';
                selectedGroupId = null;
                searchQuery = '';
                _searchController.clear();
              });
              _loadData();
            },
            isDark: isDark,
          ),
          const SizedBox(width: 6),
          _buildCompactFilterPill(
            label: 'متأخرات ($debtorsCount)',
            isSelected: activeFilter == 'debts',
            color: const Color(0xFFEF4444),
            onTap: () {
              setState(() => activeFilter = 'debts');
            },
            isDark: isDark,
          ),
          const SizedBox(width: 6),
          _buildCompactFilterPill(
            label: 'خالص السداد (${allStudents.length - debtorsCount})',
            isSelected: activeFilter == 'paid',
            color: const Color(0xFF10B981),
            onTap: () {
              setState(() => activeFilter = 'paid');
            },
            isDark: isDark,
          ),
          if (selectedGroupId != null) ...[
            const SizedBox(width: 6),
            _buildSelectedGroupPill(
              groupName: groups.where((g) => g.id == selectedGroupId).firstOrNull?.name ?? 'مجموعة',
              onClear: () {
                setState(() {
                  selectedGroupId = null;
                  _searchController.clear();
                  searchQuery = '';
                });
                _loadData();
              },
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildCompactFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    Color? color,
  }) {
    final activeColor = color ?? const Color(0xFF0284C7);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: isDark ? 0.25 : 0.15)
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              width: isSelected ? 1.3 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                Icon(Icons.check_circle_rounded, size: 12, color: activeColor),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : activeColor)
                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildSelectedGroupPill({
    required String groupName,
    required VoidCallback onClear,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onClear,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.25 : 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF8B5CF6), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_rounded, size: 12, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 4),
              Text(
                'مجموعة: $groupName',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF7C3AED),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.close_rounded, size: 12, color: Color(0xFF8B5CF6)),
            ],
          ),
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // 3. وتحتها: مربع البحث الذكي مع سهم القائمة والتقارير (Smart Search Field)
  // ---------------------------------------------------------------------------
  Widget _buildSmartSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF26354D) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(
              Icons.search_rounded,
              color: Color(0xFF0EA5E9),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'بحث ذكي (طالب، هاتف، كود، مجموعة)...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            if (searchQuery.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                tooltip: 'مسح البحث',
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchController.clear();
                  setState(() => searchQuery = '');
                  _loadData(isSearch: true);
                },
              ),
            Container(
              height: 24,
              width: 1,
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
            // The Smart Dropdown Arrow Button
            Tooltip(
              message: 'القائمة الذكية: المجموعات والتقارير ▾',
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showSmartSearchContentMenu(context, isDark);
                },
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: Color(0xFF0EA5E9),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 22,
                        color: Color(0xFF0EA5E9),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // نافذة القائمة الذكية المنبثقة (Smart Content & Navigation Menu)
  // ---------------------------------------------------------------------------
  void _showSmartSearchContentMenu(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (modalCtx) {
        return Directionality(
          textDirection: AppLocale.isArabic(context)
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            expand: false,
            builder: (ctx, scrollCtrl) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    const SizedBox(height: 10),
                    // Pull bar
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.manage_search_rounded,
                              color: Color(0xFF0EA5E9), size: 22),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'البحث الذكي والقوائم السريعة',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                'تصفية بالمجموعات والوصول المباشر للتقارير',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 1. تقارير الطالب وتقارير المجموعات
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.analytics_rounded,
                                  size: 16, color: Color(0xFF8B5CF6)),
                              SizedBox(width: 6),
                              Text(
                                'الوصول السريع للتقارير الأكاديمية والمالية',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMenuActionTile(
                                  icon: Icons.person_search_rounded,
                                  color: const Color(0xFF0EA5E9),
                                  title: 'تقارير الطالب',
                                  subtitle: 'السجل الشامل 📊',
                                  isDark: isDark,
                                  onTap: () {
                                    Navigator.pop(modalCtx);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ReportsScreen(
                                          database: widget.database,
                                          initialTab: 0,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMenuActionTile(
                                  icon: Icons.groups_3_rounded,
                                  color: const Color(0xFF10B981),
                                  title: 'تقارير المجموعات',
                                  subtitle: 'نسب الحضور والأداء 📈',
                                  isDark: isDark,
                                  onTap: () {
                                    Navigator.pop(modalCtx);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ReportsScreen(
                                          database: widget.database,
                                          initialTab: 1,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMenuActionTile(
                                  icon: Icons.request_quote_rounded,
                                  color: const Color(0xFFEF4444),
                                  title: 'تقرير المتأخرات',
                                  subtitle: '$debtorsCount طالب مدين 💳',
                                  isDark: isDark,
                                  onTap: () {
                                    Navigator.pop(modalCtx);
                                    setState(() {
                                      activeFilter = 'debts';
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMenuActionTile(
                                  icon: Icons.mark_chat_read_rounded,
                                  color: const Color(0xFF25D366),
                                  title: 'سجل الرسائل',
                                  subtitle: 'التقارير المرسلة 💬',
                                  isDark: isDark,
                                  onTap: () {
                                    Navigator.pop(modalCtx);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ReportsScreen(
                                          database: widget.database,
                                          initialTab: 2,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. تصفية وبحث في المجموعات
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.category_rounded,
                                size: 16, color: Color(0xFF3B82F6)),
                            const SizedBox(width: 6),
                            Text(
                              'بحث وتصفية بالمجموعات (${groups.length})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        if (selectedGroupId != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            icon: const Icon(Icons.clear_all_rounded, size: 16),
                            label: const Text('عرض الكل', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              Navigator.pop(modalCtx);
                              _clearSearch();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // All groups option
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: selectedGroupId == null
                              ? const Color(0xFF3B82F6)
                              : Colors.transparent,
                        ),
                      ),
                      tileColor: selectedGroupId == null
                          ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                      leading: const Icon(Icons.select_all_rounded, color: Color(0xFF3B82F6)),
                      title: const Text('جميع الطلاب (إلغاء تصفية المجموعات)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      subtitle: Text('عرض جميع المسجلين (${allStudents.length} طالب)',
                          style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        Navigator.pop(modalCtx);
                        setState(() {
                          selectedGroupId = null;
                          searchQuery = '';
                          _searchController.clear();
                        });
                        _loadData();
                      },
                    ),
                    const SizedBox(height: 6),

                    // List of groups
                    ...groups.map((grp) {
                      final isSelected = selectedGroupId == grp.id;
                      final studentCount = allStudents.where((s) => s.groupId == grp.id).length;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF0EA5E9).withValues(alpha: 0.12)
                              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF0EA5E9)
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                            width: isSelected ? 1.4 : 0.8,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF0EA5E9)
                                  : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.groups_rounded,
                              size: 16,
                              color: isSelected ? Colors.white : const Color(0xFF3B82F6),
                            ),
                          ),
                          title: Text(
                            grp.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 12.5,
                              color: isSelected ? const Color(0xFF0EA5E9) : null,
                            ),
                          ),
                          subtitle: Text(
                            '${grp.grade} • ${grp.schedule.isNotEmpty ? grp.schedule : (grp.days)}',
                            style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  '$studentCount طالب',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.bar_chart_rounded, size: 18, color: Color(0xFF8B5CF6)),
                                tooltip: 'تقرير هذه المجموعة',
                                onPressed: () {
                                  Navigator.pop(modalCtx);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReportsScreen(
                                        database: widget.database,
                                        initialTab: 1,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(modalCtx);
                            HapticFeedback.selectionClick();
                            setState(() {
                              selectedGroupId = grp.id;
                              searchQuery = '';
                              _searchController.text = grp.name;
                            });
                            _loadData();
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }


  Widget _buildMenuActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 9.5, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _StatText extends StatelessWidget {
  const _StatText({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

}

class _StudentDetailSheet extends StatefulWidget {
  const _StudentDetailSheet({
    required this.student,
    required this.database,
    required this.groups,
    required this.onEdit,
    required this.onDeleted,
    required this.onPaymentRecorded,
  });

  final StudentModel student;
  final DatabaseService database;
  final List<GroupModel> groups;
  final VoidCallback onEdit;
  final VoidCallback onDeleted;
  final VoidCallback onPaymentRecorded;

  @override
  State<_StudentDetailSheet> createState() => _StudentDetailSheetState();
}

class _StudentDetailSheetState extends State<_StudentDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String currentStudentId;
  bool _isPinRevealed = false;
  List<AttendanceModel> attendance = [];
  List<PaymentModel> payments = [];
  List<Map<String, dynamic>> examScores = [];
  List<CurriculumLessonModel> groupCurriculum = [];
  bool isLoading = true;
  late bool isStudentActive;

  @override
  void initState() {
    super.initState();
    currentStudentId = widget.student.id;
    isStudentActive = widget.student.isActive;
    _tabController = TabController(length: 6, vsync: this);
    _loadStudentDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStudentDetails() async {
    setState(() => isLoading = true);
    final att = await widget.database.getStudentAttendance(widget.student.id);
    final pay = await widget.database.getStudentPayments(widget.student.id);
    final scores = await widget.database.getStudentExamScores(
      widget.student.id,
    );

    // Curriculum
    List<CurriculumLessonModel> curr = [];
    if (widget.student.groupId != null) {
      final bindings = await widget.database.getGroupCurriculumBindings();
      final binding = bindings
          .where((b) => b['id'] == widget.student.groupId)
          .firstOrNull;
      if (binding != null && binding['curriculum_id'] != null) {
        curr = await widget.database.getCurriculumLessons(
          grade: binding['curriculum_id'] as String,
        );
      }
    }

    if (mounted) {
      setState(() {
        attendance = att;
        payments = pay;
        examScores = scores;
        groupCurriculum = curr;
        isLoading = false;
      });
    }
  }

  double get attendanceRate {
    if (attendance.isEmpty) return 100.0;
    final presentCount = attendance
        .where((a) => a.status == 'present' || a.status == 'late')
        .length;
    return (presentCount / attendance.length) * 100;
  }

  double get totalPaid {
    return payments.fold(0.0, (sum, p) => sum + p.amount);
  }

  void _sendComprehensiveReport() async {
    final cName = await widget.database.getSetting(
      'center_name',
      defaultValue: 'أكاديمية المستقبل',
    );
    final teacherName = await widget.database.getSetting(
      'teacher_name',
      defaultValue: 'الأستاذ',
    );

    final msg = StringBuffer();
    msg.writeln('📋 *تقرير متابعة شامل للطالب*');
    msg.writeln('🏛️ *$cName* | إشراف: $teacherName');
    msg.writeln('━━━━━━━━━━━━━━━━━━');
    msg.writeln('👤 *اسم الطالب:* ${widget.student.fullName}');
    msg.writeln('🆔 *كود الطالب:* ${widget.student.id}');
    msg.writeln('📚 *الصف الدراسي:* ${widget.student.grade}');
    final grp = widget.groups
        .where((g) => g.id == widget.student.groupId)
        .firstOrNull;
    if (grp != null) msg.writeln('👥 *المجموعة:* ${grp.name}');
    msg.writeln('━━━━━━━━━━━━━━━━━━');
    msg.writeln('📊 *مؤشرات الأداء والحضور:*');
    msg.writeln(
      '• نسبة الحضور: ${attendanceRate.toStringAsFixed(1)}% (${attendance.where((a) => a.status == 'present').length} من إجمالي ${attendance.length} حصة)',
    );

    if (attendance.isNotEmpty) {
      final latestAtt = attendance.first;
      msg.writeln(
        '• آخر تسميع شفوي: ${latestAtt.recitationRating ?? "غير محدد"}',
      );
      msg.writeln('• أداء الواجب: ${latestAtt.homeworkStatus ?? "تم"}');
    }

    if (examScores.isNotEmpty) {
      msg.writeln('━━━━━━━━━━━━━━━━━━');
      msg.writeln('📝 *آخر نتائج الاختبارات:*');
      for (final s in examScores.take(3)) {
        msg.writeln('• ${s['title']}: ${s['score']} / ${s['max_score']}');
      }
    }

    msg.writeln('━━━━━━━━━━━━━━━━━━');
    msg.writeln('💳 *الموقف المالي:*');
    msg.writeln('• نظام الدفع: ${widget.student.paymentPlan}');
    msg.writeln('• إجمالي المسدد: ${totalPaid.toStringAsFixed(0)} ج.م');
    msg.writeln(
      '• المتبقي / المتأخرات: ${widget.student.outstandingAmount.toStringAsFixed(0)} ج.م',
    );
    msg.writeln('━━━━━━━━━━━━━━━━━━');
    msg.writeln('نسعد دائماً بتواصلكم ومتابعتكم المستمرة 🌸');

    ReportDispatchHelper.dispatchReport(
      context: context,
      studentId: widget.student.id,
      studentName: widget.student.fullName,
      studentCode: widget.student.id,
      parentPhone: widget.student.parentPhone,
      reportTitle: 'تقرير متابعة شامل',
      reportMessage: msg.toString(),
      notifType: 'general',
    );
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final group = widget.groups
        .where((g) => g.id == widget.student.groupId)
        .firstOrNull;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Student Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Text(
                    widget.student.fullName.characters.first,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.student.fullName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isStudentActive
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isStudentActive
                                    ? Colors.green.withValues(alpha: 0.4)
                                    : Colors.amber.shade700,
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              isStudentActive ? 'نشط 🟢' : 'متوقف ⏸️',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isStudentActive
                                    ? Colors.green
                                    : Colors.amber.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${widget.student.grade} • ${group?.name ?? "بدون مجموعة"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'تعديل بيانات الطالب',
                  onPressed: widget.onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),
          // Tab bar
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(
                icon: Icon(Icons.badge_outlined, size: 20),
                text: 'نظرة عامة والباركود',
              ),
              Tab(
                icon: Icon(Icons.event_available_outlined, size: 20),
                text: 'سجل الحضور والمتابعة',
              ),
              Tab(
                icon: Icon(Icons.account_balance_wallet_outlined, size: 20),
                text: 'الماليات والتحصيلات',
              ),
              Tab(
                icon: Icon(Icons.quiz_outlined, size: 20),
                text: 'نتائج الاختبارات',
              ),
              Tab(
                icon: Icon(Icons.menu_book_outlined, size: 20),
                text: 'تقدم المنهج',
              ),
              Tab(
                icon: Icon(Icons.phonelink_lock_rounded, size: 20),
                text: 'تطبيق الطالب 📱',
              ),
            ],
          ),
          // Tab Views
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: OVERVIEW & QR
                      _buildOverviewTab(context, isDark, group),
                      // TAB 2: ATTENDANCE & SESSIONS
                      _buildAttendanceTab(context, isDark),
                      // TAB 3: FINANCES & RECEIPTS
                      _buildFinancesTab(context, isDark),
                      // TAB 4: EXAM SCORES
                      _buildExamsTab(context, isDark),
                      // TAB 5: CURRICULUM PROGRESS
                      _buildCurriculumTab(context, isDark),
                      // TAB 6: STUDENT APP CREDENTIALS & 2FA
                      _buildStudentAppTab(context, isDark),
                    ],
                  ),
          ),
        ],
      ),
    );
  }


  Widget _buildOverviewTab(
    BuildContext context,
    bool isDark,
    GroupModel? group,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Student QR Code Card
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  QrImageView(
                    data: widget.student.id,
                    version: QrVersions.auto,
                    size: 140.0,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'كود الطالب: ${widget.student.id}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'يمكن مسحه بالماسح الضوئي لتسجيل الحضور الفوري',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Quick Stats Grid
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: 'نسبة الحضور',
                  value: '${attendanceRate.toStringAsFixed(0)}%',
                  icon: Icons.check_circle_outline,
                  color: attendanceRate >= 80 ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  title: 'المتأخرات',
                  value:
                      '${widget.student.outstandingAmount.toStringAsFixed(0)} ج.م',
                  icon: Icons.money_off,
                  color: widget.student.hasOutstandingPayment
                      ? Colors.red
                      : Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  title: 'إجمالي المسدد',
                  value: '${totalPaid.toStringAsFixed(0)} ج.م',
                  icon: Icons.payments_outlined,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Action Buttons
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
            label: const Text(
              'إرسال تقرير شامل (تطبيق / واتساب) 🚀',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: _sendComprehensiveReport,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.call, color: Colors.blue),
                  label: const Text('اتصال ولي الأمر'),
                  onPressed: () =>
                      WhatsAppService.makeCall(widget.student.parentPhone),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.student.studentPhone.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.phone_android, color: Colors.teal),
                    label: const Text('اتصال بالطالب'),
                    onPressed: () =>
                        WhatsAppService.makeCall(widget.student.studentPhone),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Active / Inactive Status Switcher
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: isStudentActive ? Colors.amber.shade800 : Colors.teal,
              side: BorderSide(
                color: isStudentActive ? Colors.amber.shade700 : Colors.teal,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: Icon(
              isStudentActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
            ),
            label: Text(
              isStudentActive ? 'إيقاف نشاط الطالب مؤقتاً ⏸️' : 'تفعيل نشاط الطالب مجدداً 🟢',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final newStatus = !isStudentActive;
              await widget.database.setStudentActiveStatus(widget.student.id, newStatus);
              setState(() {
                isStudentActive = newStatus;
              });
              widget.onPaymentRecorded(); // triggers reload in parent list
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      newStatus ? 'تم تفعيل نشاط الطالب بنجاح 🟢' : 'تم إيقاف نشاط الطالب مؤقتاً ⏸️',
                    ),
                    backgroundColor: newStatus ? Colors.teal : Colors.amber.shade800,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          // Student App Quick Access Card
          _buildStudentAppOverviewCard(context, isDark),
          const SizedBox(height: 12),
          // Danger zone: Delete
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            icon: const Icon(Icons.delete_forever),
            label: const Text('حذف الطالب وسجلاته نهائياً'),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('تأكيد حذف الطالب'),
                  content: Text(
                    'هل أنت متأكد من حذف الطالب (${widget.student.fullName})؟ سيتم مسح بياناته من المركز.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('حذف نهائي'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                if (!context.mounted) return;
                final authOk = await SecurityService.authenticate(
                  context: context,
                  database: widget.database,
                  reason:
                      'تأكيد الهوية لحذف الطالب (${widget.student.fullName})',
                );
                if (authOk) {
                  await widget.database.deleteStudent(widget.student.id);
                  widget.onDeleted();
                }
              }
            },
          ),
        ],
      ),
    );
  }


  Widget _buildAttendanceTab(BuildContext context, bool isDark) {
    if (attendance.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'لا توجد سجلات حضور مسجلة لهذا الطالب بعد',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: attendance.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final rec = attendance[i];
        final isPresent = rec.status == 'present';
        final isLate = rec.status == 'late';

        return Card(
          elevation: 0,
          color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isPresent
                          ? Icons.check_circle
                          : (isLate ? Icons.alarm : Icons.cancel),
                      color: isPresent
                          ? Colors.green
                          : (isLate ? Colors.orange : Colors.red),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rec.attendanceDate,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isPresent
                            ? Colors.green.withValues(alpha: 0.15)
                            : (isLate
                                  ? Colors.orange.withValues(alpha: 0.15)
                                  : Colors.red.withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPresent ? 'حاضر' : (isLate ? 'متأخر' : 'غائب'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isPresent
                              ? Colors.green
                              : (isLate ? Colors.orange : Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
                if (rec.recitationRating != null ||
                    rec.homeworkStatus != null ||
                    (rec.notes != null && rec.notes!.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (rec.recitationRating != null)
                        Chip(
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            'تسميع: ${rec.recitationRating}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: Colors.purple.withValues(alpha: 0.1),
                        ),
                      if (rec.homeworkStatus != null)
                        Chip(
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            'الواجب: ${rec.homeworkStatus}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: Colors.teal.withValues(alpha: 0.1),
                        ),
                    ],
                  ),
                  if (rec.notes != null && rec.notes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'ملاحظات: ${rec.notes}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildFinancesTab(BuildContext context, bool isDark) {
    return Column(
      children: [
        // Balance Header Card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E3A8A), const Color(0xFF0F172A)]
                  : [const Color(0xFF2563EB), const Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'الرصيد المتبقي / المتأخرات',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '${widget.student.outstandingAmount.toStringAsFixed(0)} ج.م',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      'نظام الدفع: ${widget.student.paymentPlan}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue.shade900,
                ),
                icon: const Icon(Icons.add),
                label: const Text('سداد دفعة'),
                onPressed: () {
                  _showPaymentDialogInsideSheet();
                },
              ),
            ],
          ),
        ),
        // Receipts List
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.receipt_long, size: 18),
              const SizedBox(width: 6),
              Text(
                'سجل التحصيلات السابقة (${payments.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: payments.isEmpty
              ? Center(
                  child: Text(
                    'لا توجد دفعات مسجلة بعد',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final p = payments[i];
                    return Card(
                      elevation: 0,
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : Colors.grey.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isDark ? Colors.white12 : Colors.grey.shade200,
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green.withValues(alpha: 0.15),
                          child: const Icon(Icons.check, color: Colors.green),
                        ),
                        title: Text(
                          '${p.amount.toStringAsFixed(0)} ج.م',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${p.type} • ${p.date} ${p.note.isNotEmpty ? "\n${p.note}" : ""}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.chat_bubble_outline,
                            color: Color(0xFF25D366),
                          ),
                          tooltip: 'إرسال إيصال بالواتساب',
                          onPressed: () async {
                            final cName = await widget.database.getSetting(
                              'center_name',
                              defaultValue: 'أكاديمية المستقبل',
                            );
                            final msg = WhatsAppService.paymentReceiptMessage(
                              centerName: cName,
                              studentName: widget.student.fullName,
                              amount: p.amount,
                              type: p.type,
                              date: p.date,
                            );
                            WhatsAppService.openWhatsApp(
                              phone: widget.student.parentPhone,
                              message: msg,
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }


  void _showPaymentDialogInsideSheet() {
    final amountCtrl = TextEditingController(
      text: widget.student.outstandingAmount > 0
          ? widget.student.outstandingAmount.toStringAsFixed(0)
          : '200',
    );
    final noteCtrl = TextEditingController();
    String pType = 'اشتراك شهري';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'تحصيل من: ${widget.student.fullName}',
          overflow: TextOverflow.ellipsis,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'المبلغ المدفوع (ج.م)',
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
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: pType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'نوع التحصيل'),
                items: const [
                  DropdownMenuItem(
                    value: 'اشتراك شهري',
                    child: Text('اشتراك شهري', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'حصة فردية',
                    child: Text('حصة فردية', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'مذكرة / كتب',
                    child: Text('مذكرة / كتب', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'رسوم امتحان',
                    child: Text('رسوم امتحان', overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) pType = v;
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            child: const Text('تأكيد التحصيل'),
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (amount > 0) {
                final payment = PaymentModel(
                  studentId: widget.student.id,
                  amount: amount,
                  date: DateTime.now().toIso8601String().substring(0, 10),
                  type: pType,
                  note: noteCtrl.text.trim(),
                );
                await widget.database.recordPayment(payment);
                await WhatsAppService.autoSendPaymentReceipt(
                  database: widget.database,
                  studentName: widget.student.fullName,
                  parentPhone: widget.student.parentPhone,
                  amount: amount,
                  type: pType,
                  date: payment.date,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                _loadStudentDetails();
                widget.onPaymentRecorded();
              }
            },
          ),
        ],
      ),
    );
  }


  Widget _buildExamsTab(BuildContext context, bool isDark) {
    if (examScores.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'لا توجد اختبارات مسجلة لهذا الطالب بعد',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: examScores.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final s = examScores[i];
        final score = (s['score'] as num).toDouble();
        final maxScore = (s['max_score'] as num).toDouble();
        final pct = maxScore > 0 ? (score / maxScore) * 100 : 0.0;

        return Card(
          elevation: 0,
          color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        s['title'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s['date'] as String,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'الدرجة: $score من $maxScore (${pct.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: pct >= 85
                              ? Colors.green
                              : (pct >= 50 ? Colors.blue : Colors.red),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (pct >= 85
                                    ? Colors.green
                                    : (pct >= 50 ? Colors.blue : Colors.red))
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        pct >= 85
                            ? 'ممتاز'
                            : (pct >= 75
                                  ? 'جيد جداً'
                                  : (pct >= 50 ? 'ناجح' : 'يحتاج تحسين')),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: pct >= 85
                              ? Colors.green
                              : (pct >= 50 ? Colors.blue : Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildCurriculumTab(BuildContext context, bool isDark) {
    if (groupCurriculum.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 54,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              'لم يتم ربط منهج دراسي بمجموعة هذا الطالب بعد',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: groupCurriculum.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (ctx, i) {
        final lesson = groupCurriculum[i];
        return Card(
          elevation: 0,
          color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            title: Text(lesson.title),
            subtitle: Text(
              lesson.unitName,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        );
      },
    );
  }
  // ----------------------------------------------------
  // STUDENT APP CREDENTIALS & 2FA MANAGEMENT (SHEET)
  // ----------------------------------------------------

  String _calculateDefaultPin(Map<String, dynamic> data) {
    final parentPhone = (data['parent_phone'] ?? widget.student.parentPhone).toString().replaceAll(RegExp(r'\D'), '');
    final studentPhone = (data['student_phone'] ?? data['phone'] ?? widget.student.studentPhone).toString().replaceAll(RegExp(r'\D'), '');
    final code = (data['student_code'] ?? data['id'] ?? currentStudentId).toString().replaceAll(RegExp(r'\D'), '');

    if (parentPhone.length >= 4) {
      return parentPhone.substring(parentPhone.length - 4);
    }
    if (studentPhone.length >= 4) {
      return studentPhone.substring(studentPhone.length - 4);
    }
    if (code.length >= 4) {
      return code.substring(code.length - 4);
    }
    return '1234';
  }

  Widget _buildStudentAppOverviewCard(BuildContext context, bool isDark) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('students')
          .doc(currentStudentId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final rawCode = (data['student_code'] ?? data['id'] ?? currentStudentId).toString();
        final storedPin = (data['pin_code'] ?? '').toString().trim();
        final hasCustomPin = storedPin.isNotEmpty;
        final defaultPin = _calculateDefaultPin(data);
        final effectivePin = hasCustomPin ? storedPin : defaultPin;
        final is2FaEnabled = data['require_2fa'] != false;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: is2FaEnabled
                  ? const Color(0xFF10B981).withValues(alpha: 0.4)
                  : const Color(0xFF00F2FE).withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.phonelink_lock_rounded, color: Color(0xFF00F2FE), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'بيانات وتأمين تطبيق الطالب 📱',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                        ),
                        Text(
                          'كود 5 أرقام • رمز PIN • حماية المصادقة الثنائية 2FA',
                          style: TextStyle(fontSize: 10.5, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF00F2FE),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('إدارة الحساب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                    onPressed: () {
                      _tabController.animateTo(5);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.badge_rounded, size: 15, color: Color(0xFF00F2FE)),
                          const SizedBox(width: 4),
                          Text('كود: ', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey : Colors.grey.shade700)),
                          Text(
                            rawCode,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFF00F2FE)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(hasCustomPin ? Icons.vpn_key_rounded : Icons.lock_outline_rounded,
                              size: 15, color: hasCustomPin ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Text('PIN: ', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey : Colors.grey.shade700)),
                          Text(
                            effectivePin,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              color: hasCustomPin ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            is2FaEnabled ? Icons.verified_user_rounded : Icons.shield_outlined,
                            size: 15,
                            color: is2FaEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            is2FaEnabled ? '2FA: مفعّل' : '2FA: معطّل',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: is2FaEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentAppTab(BuildContext context, bool isDark) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('students')
          .doc(currentStudentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)));
        }

        final data = snapshot.data?.data() ?? {};
        final rawCode = (data['student_code'] ?? data['id'] ?? currentStudentId).toString();
        final sPhone = (data['student_phone'] ?? data['phone'] ?? widget.student.studentPhone).toString();
        final pPhone = (data['parent_phone'] ?? widget.student.parentPhone).toString();
        final preferredPhone = pPhone.isNotEmpty ? pPhone : sPhone;

        final storedPin = (data['pin_code'] ?? '').toString().trim();
        final hasCustomPin = storedPin.isNotEmpty;
        final defaultPin = _calculateDefaultPin(data);
        final effectivePin = hasCustomPin ? storedPin : defaultPin;

        final is2FaEnabled = data['require_2fa'] != false;
        final verifiedPhone = (data['two_fa_verified_phone'] ?? preferredPhone).toString();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                        : [const Color(0xFFE0F2FE), const Color(0xFFF0FDF4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.phonelink_lock_rounded, color: Color(0xFF00F2FE), size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.student.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'كود الطالب وكلمة مرور التطبيق ونظام المصادقة الثنائية',
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 1. Student Code Card (5 Digits)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tag_rounded, color: Color(0xFF00F2FE), size: 20),
                        const SizedBox(width: 8),
                        const Text('كود تسجيل الدخول (5 أرقام)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 14),
                          label: const Text('تعديل الكود (5 أرقام)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => _editStudentCodeInSheet(data),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            rawCode,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: Color(0xFF00F2FE),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'نسخ الكود',
                            icon: const Icon(Icons.copy_rounded, color: Color(0xFF00F2FE), size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: rawCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('تم نسخ كود الطالب ($rawCode) 📋'), duration: const Duration(seconds: 1)),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 2. PIN Code Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasCustomPin ? const Color(0xFF00F2FE).withValues(alpha: 0.4) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          hasCustomPin ? Icons.vpn_key_rounded : Icons.lock_outline_rounded,
                          color: hasCustomPin ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hasCustomPin ? 'الرمز السري (PIN) مخصص' : 'الرمز السري (PIN) الافتراضي',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        const Spacer(),
                        if (hasCustomPin)
                          TextButton(
                            onPressed: () => _resetPinInSheet(data, defaultPin),
                            child: const Text('إعادة للافتراضي', style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B))),
                          ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.password_rounded, size: 14),
                          label: const Text('تعيين رمز سري', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => _setCustomPinInSheet(data, hasCustomPin ? storedPin : null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _isPinRevealed ? effectivePin : '••••',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: _isPinRevealed ? 3 : 4,
                              color: hasCustomPin ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: _isPinRevealed ? 'إخفاء' : 'إظهار',
                            icon: Icon(_isPinRevealed ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                            onPressed: () => setState(() => _isPinRevealed = !_isPinRevealed),
                          ),
                          IconButton(
                            tooltip: 'نسخ الرمز',
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: effectivePin));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('تم نسخ الرمز السري ($effectivePin) 📋'), duration: const Duration(seconds: 1)),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasCustomPin
                          ? '• تم تعيين هذا الرمز بواسطة الطالب أو المعلم'
                          : '• الرمز الافتراضي: آخر 4 أرقام من هاتف ولي الأمر أو كود الطالب',
                      style: TextStyle(fontSize: 10.5, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 3. 2FA Security Switch Card (Mandatory Phone & WhatsApp Confirmation)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: is2FaEnabled ? const Color(0xFF10B981).withValues(alpha: 0.4) : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          is2FaEnabled ? Icons.verified_user_rounded : Icons.phonelink_erase_rounded,
                          color: is2FaEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                is2FaEnabled ? 'المصادقة الثنائية (2FA): مفعلة 🛡️' : 'المصادقة الثنائية (2FA): معطلة ⚠️',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                  color: is2FaEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                ),
                              ),
                              Text(
                                is2FaEnabled
                                    ? 'الهاتف المعتمد: $verifiedPhone'
                                    : 'إلزام الطالب بإدخال رقم الهاتف المسجل للدخول',
                                style: TextStyle(fontSize: 10.5, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: is2FaEnabled,
                          activeThumbColor: const Color(0xFF10B981),
                          activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.35),
                          inactiveTrackColor: Colors.grey.shade800,
                          onChanged: (_) => _handle2FaToggleInSheet(data, is2FaEnabled),
                        ),
                      ],
                    ),
                    if (is2FaEnabled) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF10B981)),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'لن يتمكن أي شخص من فتح التطبيق إلا بإدخال هذا الهاتف المعتمد والرمز السري.',
                                style: TextStyle(fontSize: 10.5, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 4. WhatsApp Share Credentials Button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.chat_rounded, size: 20),
                label: const Text(
                  'إرسال بيانات الدخول للطالب وولي الأمر واتساب 📲',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                onPressed: () => _sendStudentCredentialsViaWhatsApp(
                  studentName: widget.student.fullName,
                  studentCode: rawCode,
                  pin: effectivePin,
                  phone: preferredPhone,
                  is2Fa: is2FaEnabled,
                ),
              ),

              const SizedBox(height: 10),

              // 5. Force Revoke Session & Open All Students App Control
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('تسجيل خروج من الأجهزة 🔒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                      ),
                      onPressed: () => _forceRevokeSessionInSheet(data),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00F2FE),
                        side: const BorderSide(color: Color(0xFF00F2FE)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.dashboard_customize_rounded, size: 16),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('لوحة كل الطلاب 📱', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TeacherStudentAppControlScreen(database: widget.database),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendStudentCredentialsViaWhatsApp({
    required String studentName,
    required String studentCode,
    required String pin,
    required String phone,
    required bool is2Fa,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رقم هاتف مسجل لهذا الطالب لإرسال البيانات إليه'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final message = '''
🎓 *بيانات تسجيل الدخول لتطبيق الطالب - Edu Academy*

مرحباً بك، إليك بيانات الدخول الرسمية الخاصة بالطالب:
👤 *اسم الطالب:* $studentName
🆔 *كود الطالب:* $studentCode
🔒 *الرمز السري (PIN):* $pin
🛡️ *المصادقة الثنائية:* ${is2Fa ? 'مفعلة (يمكنك كتابة رقم الهاتف للتحقق)' : 'معطلة (الدخول بالكود والرمز السري فقط)'}

📲 *لتحميل وتثبيت التطبيق على هاتفك:*
تأكد من فتح تطبيق الطالب وإدخال الكود والرمز السري كما هو موضح أعلاه.
نتمنى لكم دوام التفوق والنجاح! 🌟
''';

    await WhatsAppService.openWhatsApp(
      phone: cleanPhone,
      message: message,
      database: widget.database,
      studentId: currentStudentId,
      studentName: studentName,
      category: 'login_credentials',
    );
  }

  Future<void> _forceRevokeSessionInSheet(Map<String, dynamic> data) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('تسجيل خروج إجباري', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'هل ترغب في تسجيل خروج إجباري للطالب من جميع الهواتف والأجهزة؟\nسيتعين عليه إدخال الكود والرمز السري مجدداً للدخول.',
          style: TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تسجيل خروج فوراً 🔒'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('students')
          .doc(currentStudentId)
          .set({
        'session_revoked_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنهاء جلسة الطالب وتسجيل الخروج من كافة الأجهزة بنجاح 🔒'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تسجيل الخروج: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _editStudentCodeInSheet(Map<String, dynamic> data) async {
    final currentCode = (data['student_code'] ?? currentStudentId).toString().replaceAll(RegExp(r'\D'), '');
    String suggested = currentCode;
    if (suggested.length != 5) {
      suggested = await widget.database.generateUniqueRandom5DigitCode();
    }

    final codeCtrl = TextEditingController(text: suggested);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
          ),
          title: const Row(
            children: [
              Icon(Icons.casino_rounded, color: Color(0xFF00F2FE)),
              SizedBox(width: 8),
              Expanded(
                child: Text('كود عشوائي للطالب (5 أرقام) 🎲', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تعديل كود تسجيل الدخول الخاص بالطالب: (${widget.student.fullName})',
                    style: TextStyle(fontSize: 12.5, color: isDark ? const Color(0xFFCBD5E1) : Colors.black87)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2),
                  decoration: InputDecoration(
                    labelText: 'كود الطالب (5 أرقام عشوائية) *',
                    hintText: 'مثال: 48291',
                    prefixIcon: const Icon(Icons.badge_rounded, color: Color(0xFF00F2FE)),
                    suffixIcon: IconButton(
                      tooltip: 'توليد كود عشوائي جديد 🎲',
                      icon: const Icon(Icons.casino_rounded, color: Color(0xFF00F2FE)),
                      onPressed: () async {
                        final r = await widget.database.generateUniqueRandom5DigitCode();
                        codeCtrl.text = r;
                      },
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (val) {
                    final clean = (val ?? '').trim().replaceAll(RegExp(r'\D'), '');
                    if (clean.length != 5) {
                      return 'يجب أن يتكون كود الطالب من 5 أرقام بالضبط (مثال: 48291)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                const Text('🎲 الكود العشوائي غير المسلسل يمنع التخمين ويزيد من خصوصية حساب الطالب.',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00F2FE), foregroundColor: Colors.black87),
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final newCode = codeCtrl.text.trim();
                  Navigator.pop(ctx);

                  final oldId = currentStudentId;
                  try {
                    // 1. Update SQLite cascade
                    await widget.database.updateStudentIdCascade(oldId, newCode);

                    // 2. Update Firestore
                    final firestore = FirebaseFirestore.instance;
                    final col = firestore.collection('academies').doc('default').collection('students');

                    final oldDoc = await col.doc(oldId).get();
                    Map<String, dynamic> docData = {};
                    if (oldDoc.exists && oldDoc.data() != null) {
                      docData = Map<String, dynamic>.from(oldDoc.data()!);
                    }
                    docData['id'] = newCode;
                    docData['student_code'] = newCode;
                    docData['updated_at'] = FieldValue.serverTimestamp();

                    await col.doc(newCode).set(docData, SetOptions(merge: true));
                    if (oldId != newCode) {
                      await col.doc(oldId).delete();
                    }

                    try {
                      await CloudSyncService.instance.syncStudents();
                    } catch (_) {}

                    setState(() {
                      currentStudentId = newCode;
                    });
                    widget.onPaymentRecorded();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم تعديل كود الطالب إلى ($newCode) وحفظه بنجاح 🔢'),
                          backgroundColor: const Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('Error updating student code: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء حفظ الكود: $e'),
                          backgroundColor: const Color(0xFFEF4444),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('حفظ الكود 5 أرقام', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handle2FaToggleInSheet(Map<String, dynamic> data, bool currentVal) async {
    if (currentVal) {
      // Disabling 2FA
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('تعطيل المصادقة الثنائية ⚠️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: const Text(
            'هل أنت متأكد من رغبتك في تعطيل المصادقة الثنائية؟ سيتمكن الطالب من الدخول بالكود والرمز السري فقط دون التحقق من رقم الهاتف.',
            style: TextStyle(fontSize: 12.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تعطيل الحماية'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      await FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('students')
          .doc(currentStudentId)
          .set({
        'require_2fa': false,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تعطيل المصادقة الثنائية بنجاح ⚠️'),
            backgroundColor: Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // ENABLING 2FA: Mandatory Phone Number & WhatsApp Confirmation
    final currentPhone = (data['two_fa_verified_phone'] ??
            data['student_phone'] ??
            data['parent_phone'] ??
            data['phone'] ??
            widget.student.parentPhone.isNotEmpty
        ? widget.student.parentPhone
        : widget.student.studentPhone)
        .toString()
        .replaceAll(RegExp(r'\D'), '');

    final phoneController = TextEditingController(text: currentPhone);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
            ),
            title: const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('تفعيل المصادقة الثنائية (2FA) 🛡️',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'لتأمين حساب الطالب (${widget.student.fullName})، إدخال رقم الهاتف إجباري للتحقق وإرسال رسالة التأكيد عبر واتساب:',
                      style: TextStyle(fontSize: 12.5, color: isDark ? const Color(0xFFCBD5E1) : Colors.black87),
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      autofocus: true,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف المعتمد للتحقق *',
                        hintText: '010XXXXXXXX',
                        prefixIcon: const Icon(Icons.phone_android_rounded, color: Color(0xFF10B981)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (val) {
                        final clean = (val ?? '').replaceAll(RegExp(r'\D'), '');
                        if (clean.length < 10) {
                          return 'يجب إدخال رقم هاتف صحيح مكون من 10 أرقام على الأقل';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'سيقوم التطبيق بإرسال رسالة تأكيد رسمية عبر الواتساب إلى هذا الرقم فور التفعيل للتحقق.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF25D366), fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('تأكيد وإرسال واتساب 💬', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  if (formKey.currentState?.validate() ?? false) {
                    final cleanPhone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
                    Navigator.pop(ctx);

                    // 1. Save in Firestore
                    final updateData = <String, dynamic>{
                      'require_2fa': true,
                      'two_fa_verified_phone': cleanPhone,
                      'phone': cleanPhone,
                      'updated_at': FieldValue.serverTimestamp(),
                    };

                    await FirebaseFirestore.instance
                        .collection('academies')
                        .doc('default')
                        .collection('students')
                        .doc(currentStudentId)
                        .set(updateData, SetOptions(merge: true));

                    // 2. Send WhatsApp Confirmation Message
                    final sName = widget.student.fullName;
                    final sCode = (data['student_code'] ?? currentStudentId).toString();
                    final sPin = (data['pin_code'] ?? _calculateDefaultPin(data)).toString();

                    final confirmMsg = '''
🔐 *تأكيد تفعيل المصادقة الثنائية (2FA) - تطبيق Edu Academy*

مرحباً بك،
تم بنجاح تفعيل نظام التحقق برقم الهاتف لحساب الطالب:
👤 *اسم الطالب:* $sName
🆔 *كود الطالب:* $sCode
🔒 *الرمز السري (PIN):* $sPin
📱 *رقم الهاتف المعتمد للدخول:* $cleanPhone

━━━━━━━━━━━━━━━━━━
⚠️ *تنبيه أمان:* تم تأمين الحساب ولن يتمكن أي شخص من فتح التطبيق إلا بإدخال هذا الرقم المعتمد والرمز السري.
نتمنى لكم دوام التفوق والنجاح! 🌟
''';

                    await WhatsAppService.openWhatsApp(
                      phone: cleanPhone,
                      message: confirmMsg,
                      database: widget.database,
                      studentId: currentStudentId,
                      studentName: sName,
                      category: 'security',
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم تفعيل المصادقة الثنائية وجاري إرسال رسالة التأكيد عبر واتساب 💬'),
                          backgroundColor: Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setCustomPinInSheet(Map<String, dynamic> data, String? currentPin) async {
    final pinController = TextEditingController(text: currentPin ?? '');
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.password_rounded, color: Color(0xFF00F2FE)),
                SizedBox(width: 8),
                Text('تعيين رمز سري (PIN) 🔑', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أدخل الرمز السري الجديد لدخول الطالب (${widget.student.fullName}):',
                  style: const TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                if (dialogError != null) ...[
                  Text(dialogError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: pinController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: isDark ? const Color(0xFF00F2FE) : const Color(0xFF0284C7),
                  ),
                  decoration: InputDecoration(
                    hintText: 'مثال: 5544 أو s2026',
                    hintStyle: const TextStyle(letterSpacing: 1, fontSize: 13, color: Colors.grey),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F2FE),
                  foregroundColor: const Color(0xFF050B14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final newPin = pinController.text.trim();
                  if (newPin.length < 4) {
                    setDialogState(() => dialogError = 'يجب أن يتكون الرمز من 4 خانات على الأقل');
                    return;
                  }

                  Navigator.pop(ctx);
                  try {
                    await FirebaseFirestore.instance
                        .collection('academies')
                        .doc('default')
                        .collection('students')
                        .doc(currentStudentId)
                        .set({
                      'pin_code': newPin,
                      'updated_at': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم تعيين الرمز السري بنجاح ($newPin) 🔑'),
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ أثناء حفظ الرمز: $e'), backgroundColor: const Color(0xFFEF4444)),
                      );
                    }
                  }
                },
                child: const Text('حفظ الرمز السري', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _resetPinInSheet(Map<String, dynamic> data, String defaultPin) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text('استعادة الرمز الافتراضي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'هل ترغب في حذف الرمز المخصص واستعادة الرمز الافتراضي ($defaultPin)؟',
          style: const TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الاستعادة'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('students')
          .doc(currentStudentId)
          .set({
        'pin_code': '',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم استعادة الرمز الافتراضي ($defaultPin) بنجاح 🔄'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الاستعادة: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
