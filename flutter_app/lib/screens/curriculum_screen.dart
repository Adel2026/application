import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/curriculum_excel_service.dart';
import '../core/database/database_service.dart';
import '../models/curriculum_model.dart';
import '../models/group_model.dart';
import '../models/student_model.dart';
import '../widgets/section_top_bar.dart';
import 'teacher_materials_hub_screen.dart';

class GroupCurriculumBinding {
  final String groupId;
  String groupName;
  String gradeBadge;
  String curriculumName;
  String track = 'لغات'; // 'لغات' or 'عربي'
  bool isLocked;
  Color dotColor;

  GroupCurriculumBinding({
    required this.groupId,
    required this.groupName,
    required this.gradeBadge,
    required this.curriculumName,
    this.track = 'لغات',
    this.isLocked = true,
    this.dotColor = const Color(0xFF3B82F6),
  });

  Map<String, dynamic> toMap() => {
    'id': groupId,
    'group_name': groupName,
    'grade_badge': gradeBadge,
    'curriculum_name': curriculumName,
    'track': track,
    'is_locked': isLocked ? 1 : 0,
    'color_dot': dotColor.toARGB32(),
    'updated_at': DateTime.now().toIso8601String(),
  };

  factory GroupCurriculumBinding.fromMap(
    Map<String, dynamic> map,
    GroupModel group,
  ) => GroupCurriculumBinding(
    groupId: group.id,
    groupName: group.name,
    gradeBadge: group.grade.isNotEmpty
        ? group.grade
        : (map['grade_badge'] as String? ?? 'عام'),
    curriculumName:
        map['curriculum_name'] as String? ??
        (group.grade.isNotEmpty ? 'منهج ${group.grade}' : 'المنهج الدراسي'),
    track: map['track'] as String? ?? 'لغات',
    isLocked: (map['is_locked'] as num?)?.toInt() != 0,
    dotColor: Color((map['color_dot'] as num?)?.toInt() ?? 0xFF3B82F6),
  );
}

class _ParsedCurriculumFile {
  final String fileName;
  final String filePath;
  List<CurriculumLessonModel> lessons;
  String curriculumName;
  String grade;
  String stage;
  String subject;
  String track = 'لغات';
  List<String> uniqueUnits;

  _ParsedCurriculumFile({
    required this.fileName,
    required this.filePath,
    required this.lessons,
    required this.curriculumName,
    required this.grade,
    required this.stage,
    required this.subject,
    required this.uniqueUnits,
  });
}

class CurriculumScreen extends StatefulWidget {
  const CurriculumScreen({
    super.key,
    required this.database,
    this.initialStage,
    this.onBack,
  });

  final DatabaseService database;
  final String? initialStage;
  final VoidCallback? onBack;

  @override
  State<CurriculumScreen> createState() => _CurriculumScreenState();
}

class _CurriculumScreenState extends State<CurriculumScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<GroupModel> groups = [];
  List<CurriculumLessonModel> lessons = [];
  List<SessionLogModel> sessionLogs = [];
  List<GroupCurriculumBinding> groupBindings = [];
  List<StudentModel> allStudents = [];
  bool isLoading = true;

  String selectedStageFilter = 'الكل';
  bool isSelectionMode = false;
  final Set<String> selectedCurricula = {};

  void _toggleSelectionMode(String initialKey) {
    setState(() {
      isSelectionMode = true;
      selectedCurricula.add(initialKey);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      isSelectionMode = false;
      selectedCurricula.clear();
    });
  }

  void _toggleCurriculumSelected(String key) {
    setState(() {
      if (selectedCurricula.contains(key)) {
        selectedCurricula.remove(key);
        if (selectedCurricula.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedCurricula.add(key);
      }
    });
  }

  void _toggleSelectAll(List<String> visibleGrades) {
    setState(() {
      if (selectedCurricula.length == visibleGrades.length) {
        selectedCurricula.clear();
        isSelectionMode = false;
      } else {
        selectedCurricula.addAll(visibleGrades);
      }
    });
  }

  static String _normalizeArabicText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
  }

  static const List<List<String>> _gradeOrderMarkers = [
    // 0: رابعة ابتدائي / Prim 4
    [
      'pri 4', 'pri4', 'prim 4', 'prim4', 'p4', 'primary 4', 'grade 4',
      'الرابع الابتدائي', 'الرابع الابتدائى', 'رابع ابتدائي', 'رابعه ابتدائي', 'رابعة ابتدائي', 'الصف الرابع',
    ],
    // 1: خامسة ابتدائي / Prim 5
    [
      'pri 5', 'pri5', 'prim 5', 'prim5', 'p5', 'primary 5', 'grade 5',
      'الخامس الابتدائي', 'الخامس الابتدائى', 'خامس ابتدائي', 'خامسه ابتدائي', 'خامسة ابتدائي', 'الصف الخامس',
    ],
    // 2: سادسة ابتدائي / Prim 6
    [
      'pri 6', 'pri6', 'prim 6', 'prim6', 'p6', 'primary 6', 'grade 6',
      'السادس الابتدائي', 'السادس الابتدائى', 'سادس ابتدائي', 'سادسه ابتدائي', 'سادسة ابتدائي', 'الصف السادس',
    ],
    // 3: أولى إعدادي / Prep 1
    [
      'prep 1', 'prep1', 'middle 1',
      'الأول الإعدادي', 'الاول الاعدادي', 'الاول الاعدادى', 'اول اعدادي', 'اولى اعدادي', 'أولى إعدادي', 'الصف الأول الإعدادي', 'الصف الاول الاعدادي',
    ],
    // 4: تانية إعدادي / Prep 2
    [
      'prep 2', 'prep2', 'middle 2',
      'الثاني الإعدادي', 'الثاني الاعدادي', 'الثاني الاعدادى', 'ثاني اعدادي', 'تاني اعدادي', 'ثانية إعدادي', 'تانية اعدادي', 'الصف الثاني الإعدادي', 'الصف الثاني الاعدادي',
    ],
    // 5: تالتة إعدادي / Prep 3
    [
      'prep 3', 'prep3', 'middle 3',
      'الثالث الإعدادي', 'الثالث الاعدادي', 'الثالث الاعدادى', 'ثالث اعدادي', 'تالت اعدادي', 'ثالثة إعدادي', 'تالتة اعدادي', 'الصف الثالث الإعدادي', 'الصف الثالث الاعدادي',
    ],
    // 6: أولى ثانوي / Sec 1
    [
      'sec 1', 'sec1', 'secondary 1',
      'الأول الثانوي', 'الاول الثانوي', 'اول ثانوي', 'اولى ثانوي', 'أولى ثانوي', 'الصف الأول الثانوي', 'الصف الاول الثانوي',
    ],
    // 7: تانية ثانوي / Sec 2
    [
      'sec 2', 'sec2', 'secondary 2',
      'الثاني الثانوي', 'ثاني ثانوي', 'تاني ثانوي', 'ثانية ثانوي', 'تانية ثانوي', 'الصف الثاني الثانوي',
    ],
    // 8: تالتة ثانوي / Sec 3
    [
      'sec 3', 'sec3', 'secondary 3',
      'الثالث الثانوي', 'ثالث ثانوي', 'تالت ثانوي', 'ثالثة ثانوي', 'تالتة ثانوي', 'الصف الثالث الثانوي',
    ],
  ];

  int _gradeOrder(String grade) {
    final normalized = _normalizeArabicText(grade);
    for (var index = 0; index < _gradeOrderMarkers.length; index++) {
      if (_gradeOrderMarkers[index].any(
        (marker) => normalized.contains(_normalizeArabicText(marker)),
      )) {
        return index;
      }
    }
    // Fallback based on stage keywords
    if (normalized.contains('ابتدائ') || normalized.contains('pri')) return 2;
    if (normalized.contains('اعداد') || normalized.contains('prep')) return 5;
    if (normalized.contains('ثانوي') || normalized.contains('sec')) return 8;
    return _gradeOrderMarkers.length + 10;
  }

  List<String> _sortGrades(Iterable<String> grades) {
    final result = grades.toSet().toList();
    result.sort((first, second) {
      final order = _gradeOrder(first).compareTo(_gradeOrder(second));
      return order != 0 ? order : first.compareTo(second);
    });
    return result;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.initialStage != null && widget.initialStage!.isNotEmpty) {
      selectedStageFilter = widget.initialStage!;
    }
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (groups.isEmpty) {
      setState(() => isLoading = true);
    }
    try {
      final results = await Future.wait([
        widget.database.getGroups(),
        widget.database.getCurriculumLessons(),
        widget.database.getSessionLogs(),
        widget.database.getGroupCurriculumBindings(),
        widget.database.getStudents(),
      ]);

      final gList = results[0] as List<GroupModel>;
      final lList = results[1] as List<CurriculumLessonModel>;
      final sList = results[2] as List<SessionLogModel>;
      final rawBindings = results[3] as List<Map<String, dynamic>>;
      final stdList = results[4] as List<StudentModel>;

      final Map<String, Map<String, dynamic>> savedBindingsMap = {
        for (final row in rawBindings) (row['id'] as String? ?? ''): row,
      };

      final List<GroupCurriculumBinding> items = [];
      for (final g in gList) {
        if (savedBindingsMap.containsKey(g.id)) {
          final row = savedBindingsMap[g.id]!;
          final cName = (row['curriculum_name'] as String? ?? '').trim();
          if (cName.isNotEmpty) {
            items.add(GroupCurriculumBinding.fromMap(row, g));
          }
        }
      }

      if (mounted) {
        setState(() {
          groups = gList;
          lessons = lList;
          sessionLogs = sList;
          groupBindings = items;
          allStudents = stdList;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading curriculum: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- Curriculum Groups and Progress Calculation ---
  List<String> get uniqueGrades {
    final set = <String>{};
    for (final l in lessons) {
      final curName = (l.curriculumName ?? '').trim();
      final gradeName = l.grade.trim();
      final name = curName.isNotEmpty ? curName : gradeName;
      if (name.isNotEmpty) set.add(name);
    }
    for (final b in groupBindings) {
      final cName = b.curriculumName.trim();
      if (cName.isNotEmpty) set.add(cName);
    }
    return _sortGrades(set);
  }

  List<CurriculumLessonModel> _getLessonsForCurriculum(String nameOrGrade) {
    final trimmed = nameOrGrade.trim();
    final clean = trimmed.replaceFirst(RegExp(r'^منهج\s+'), '').trim();
    final withManhaj = 'منهج $clean';

    return lessons.where((l) {
      final lCur = (l.curriculumName ?? '').trim();
      final lGrade = l.grade.trim();
      final lEffectiveName = lCur.isNotEmpty ? lCur : lGrade;

      if (lEffectiveName == trimmed) return true;
      if (lCur.isNotEmpty) {
        return lCur == clean || lCur == withManhaj;
      }
      return lGrade == clean || lGrade == withManhaj || 'منهج $lGrade' == trimmed;
    }).toList();
  }

  double _calculateProgress(List<CurriculumLessonModel> lessonList) {
    if (lessonList.isEmpty) return 0.0;
    final done = lessonList.where((l) => l.isCompleted).length;
    return done / lessonList.length;
  }

  List<GroupModel> _getGroupsBoundTo(String curriculumName, [String? grade]) {
    final trimmed = curriculumName.trim();
    final clean = trimmed.replaceFirst(RegExp(r'^منهج\s+'), '').trim();
    final parenMatch = RegExp(r'\((.*?)\)').firstMatch(curriculumName);
    final insideParen = parenMatch?.group(1)?.trim();

    final boundGroupIds = groupBindings
        .where((b) {
          final bCur = b.curriculumName.trim();
          final bClean = bCur.replaceFirst(RegExp(r'^منهج\s+'), '').trim();
          if (bCur.isEmpty) return false;
          return bCur == trimmed ||
              bCur == clean ||
              bCur == 'منهج $clean' ||
              (clean.isNotEmpty &&
                  (bClean == clean ||
                      (clean.length > 3 && bClean.contains(clean)))) ||
              (insideParen != null &&
                  insideParen.isNotEmpty &&
                  (bCur == insideParen || bClean == insideParen)) ||
              (grade != null &&
                  grade.trim().isNotEmpty &&
                  (bCur == grade.trim() || bClean == grade.trim()));
        })
        .map((b) => b.groupId)
        .toSet();

    return groups.where((g) => boundGroupIds.contains(g.id)).toList();
  }

  Future<void> _confirmDeleteCurricula(List<String> targets) async {
    if (targets.isEmpty) return;

    final allBoundGroups = <GroupModel>[];
    for (final key in targets) {
      final bgs = _getGroupsBoundTo(key, key);
      for (final bg in bgs) {
        if (!allBoundGroups.any((g) => g.id == bg.id)) {
          allBoundGroups.add(bg);
        }
      }
    }

    bool deleteBoundGroups = false;
    final isSingle = targets.length == 1;
    final title = isSingle
        ? 'حذف منهج "${targets.first}"'
        : 'حذف ${targets.length} مناهج دراسية';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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
                    Text(
                      isSingle
                          ? 'هل أنت متأكد من رغبتك في حذف هذا المنهج نهائياً؟ سيتم مسح كافة الوحدات والدروس الخاصة به.'
                          : 'هل أنت متأكد من رغبتك في حذف المناهج المحددة (${targets.length}) نهائياً؟ سيتم مسح جميع الوحدات والدروس التابعة لها.',
                      style: const TextStyle(fontSize: 13.5, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    if (allBoundGroups.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.link_off_rounded,
                                  color: Colors.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'مجموعات مرتبطة (${allBoundGroups.length}):',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              allBoundGroups.map((g) => g.name).join(' • '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: deleteBoundGroups
                              ? Colors.red.withValues(alpha: 0.08)
                              : (isDark
                                    ? const Color(0xFF1E293B)
                                    : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: deleteBoundGroups
                                ? Colors.red.withValues(alpha: 0.4)
                                : Colors.transparent,
                          ),
                        ),
                        child: CheckboxListTile(
                          dense: true,
                          value: deleteBoundGroups,
                          activeColor: Colors.red,
                          title: const Text(
                            'حذف المجموعات المرتبطة أيضاً نهائياً',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: Colors.red,
                            ),
                          ),
                          subtitle: const Text(
                            'تحذير: سيتم حذف بيانات الطلاب والحضور والاشتراكات لهذه المجموعات',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          onChanged: (val) {
                            setDialogState(() {
                              deleteBoundGroups = val ?? false;
                            });
                          },
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.grey,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'لا توجد أي مجموعات دراسية مرتبطة بهذه المناهج حالياً.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.delete_forever_rounded, size: 18),
                  label: const Text('تأكيد الحذف'),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      setState(() => isLoading = true);
      try {
        await widget.database.deleteCurriculaBatch(
          targets,
          deleteBoundGroups: deleteBoundGroups,
        );
        _exitSelectionMode();
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                deleteBoundGroups
                    ? 'تم حذف المناهج والمجموعات المرتبطة بنجاح'
                    : 'تم حذف المناهج بنجاح',
              ),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ أثناء الحذف: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _confirmUnbindGroup(
    GroupModel group,
    String curriculumName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.link_off_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text(
              'فك ربط المجموعة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'هل تريد فك ربط مجموعة "${group.name}" من منهج "$curriculumName"؟ لن يتم حذف المجموعة أو طلابها.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('فك الربط'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => isLoading = true);
      await widget.database.unbindGroupFromCurriculum(
        group.id,
        groupName: group.name,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم فك ربط مجموعة "${group.name}" بنجاح'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    }
  }

  // --- Dialogs & Sheets ---
  Future<void> _showRenameCurriculumDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: Colors.blueAccent, size: 26),
            SizedBox(width: 8),
            Text(
              'تسمية المنهج الدراسي',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'يمكنك تغيير وتعديل اسم المنهج الدراسي بحرية تامة:',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم المنهج الجديد',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.menu_book),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'يرجى إدخال اسم المنهج';
                  }
                  return null;
                },
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
              backgroundColor: const Color(0xFF2563EB),
            ),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('حفظ الاسم'),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newName = controller.text.trim();
      if (newName != currentName && newName.isNotEmpty) {
        setState(() => isLoading = true);
        try {
          await widget.database.renameCurriculum(
            oldName: currentName,
            newName: newName,
          );
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تمت إعادة تسمية المنهج إلى "$newName" بنجاح ✅'),
                backgroundColor: const Color(0xFF10B981),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('حدث خطأ أثناء تعديل الاسم: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => isLoading = false);
        }
      }
    }
  }

  Future<void> _showEditCurriculumDialog(String currentName) async {
    final curLessons = _getLessonsForCurriculum(currentName);
    final curGrade = curLessons.isNotEmpty
        ? curLessons.first.grade
        : currentName;
    final curSubject = curLessons.isNotEmpty ? curLessons.first.subject : 'عام';

    final binding = groupBindings
        .where((b) => b.curriculumName == currentName)
        .firstOrNull;
    String selectedTrack = binding?.track ?? 'لغات';

    final nameCtrl = TextEditingController(text: currentName);
    final subjectCtrl = TextEditingController(text: curSubject);
    String selectedGrade = curGrade;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.tune_rounded, color: Colors.indigo, size: 24),
              SizedBox(width: 8),
              Text(
                'تعديل بيانات المنهج',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المنهج الدراسي',
                    prefixIcon: Icon(Icons.menu_book),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المادة الدراسية',
                    prefixIcon: Icon(Icons.category),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: uniqueGrades.contains(selectedGrade)
                      ? selectedGrade
                      : null,
                  hint: Text(selectedGrade),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'الصف الدراسي',
                    prefixIcon: Icon(Icons.school),
                  ),
                  items: _sortGrades([
                    'الصف الرابع الابتدائي (Prim 4)',
                    'الصف الخامس الابتدائي (Prim 5)',
                    'الصف السادس الابتدائي (Prim 6)',
                    'الصف الأول الإعدادي (Prep 1)',
                    'الصف الثاني الإعدادي (Prep 2)',
                    'الصف الثالث الإعدادي (Prep 3)',
                    'الصف الأول الثانوي (Sec 1)',
                    'الصف الثاني الثانوي (Sec 2)',
                    'الصف الثالث الثانوي (Sec 3)',
                    ...uniqueGrades,
                  ]).map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) =>
                      setDState(() => selectedGrade = v ?? selectedGrade),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedTrack,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'المسار التعليمي',
                    prefixIcon: Icon(Icons.language),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'لغات',
                      child: Text('لغات (Languages)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'عربي',
                      child: Text('عربي (Arabic)', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (v) =>
                      setDState(() => selectedTrack = v ?? 'لغات'),
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
                backgroundColor: const Color(0xFF2563EB),
              ),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('حفظ التعديلات'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final newName = nameCtrl.text.trim().isNotEmpty
          ? nameCtrl.text.trim()
          : currentName;
      setState(() => isLoading = true);
      try {
        await widget.database.updateCurriculumInfo(
          currentName: currentName,
          newName: newName,
          subject: subjectCtrl.text.trim(),
          grade: selectedGrade,
          track: selectedTrack,
        );
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تحديث بيانات المنهج "$newName" بنجاح ✅'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ أثناء التحديث: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => isLoading = false);
      }
    }
  }

  void _showCurriculumOptionsMenu(String curriculumKey) {
    final curLessons = _getLessonsForCurriculum(curriculumKey);
    final boundGroups = _getGroupsBoundTo(curriculumKey, curriculumKey);

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.menu_book,
                        color: Colors.indigo,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            curriculumKey,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${curLessons.length} درساً • ${boundGroups.length} مجموعات مرتبطة',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // 1. Rename
                ListTile(
                  leading: const Icon(
                    Icons.drive_file_rename_outline,
                    color: Colors.blueAccent,
                  ),
                  title: const Text(
                    'تغيير اسم المنهج (تسمية)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'تعديل اسم المنهج في كل الدروس والمجموعات المرتبطة',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showRenameCurriculumDialog(curriculumKey);
                  },
                ),

                // 2. Edit Info
                ListTile(
                  leading: const Icon(Icons.tune_rounded, color: Colors.teal),
                  title: const Text(
                    'تعديل بيانات المنهج',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'تعديل المادة أو الصف الدراسي أو المسار',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditCurriculumDialog(curriculumKey);
                  },
                ),

                // 3. Add Lesson
                ListTile(
                  leading: const Icon(
                    Icons.add_task_rounded,
                    color: Colors.purple,
                  ),
                  title: const Text(
                    'إضافة درس جديد لهذا المنهج',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAddLessonDialog(prefillCurriculum: curriculumKey);
                  },
                ),

                // 4. Bind Groups
                ListTile(
                  leading: const Icon(Icons.link_rounded, color: Colors.orange),
                  title: const Text(
                    'ربط المجموعات بالمنهج',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${boundGroups.length} مجموعات مرتبطة حالياً',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showBindCurriculumToGroupsSheet(
                      curriculumKey,
                      curriculumKey,
                    );
                  },
                ),

                // 5. Multi-select
                ListTile(
                  leading: const Icon(
                    Icons.checklist_rounded,
                    color: Colors.blueGrey,
                  ),
                  title: const Text(
                    'تفعيل التحديد المتعدد',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'تحديد هذا المنهج ومناهج أخرى للحذف الجماعي',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleSelectionMode(curriculumKey);
                  },
                ),

                // 6. Delete Curriculum
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'حذف هذا المنهج',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'حذف المنهج ودروسه مع خيار فك الربط أو حذف المجموعات',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteCurricula([curriculumKey]);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddCurriculumDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'إضافة منهج دراسي جديد',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'اختر طريقة إضافة المنهج الدراسي:',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.teal.shade300),
                ),
                tileColor: Colors.teal.withValues(alpha: 0.08),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.file_upload_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                title: const Text(
                  'استيراد منهج كامل من ملف (Excel / CSV)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'إضافة المنهج بجميع وحداته ودروسه وتفاصيله دفعة واحدة',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _importCurriculumFromExcel();
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.blue.shade300),
                ),
                tileColor: Colors.blue.withValues(alpha: 0.08),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.edit_note_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                title: const Text(
                  'إنشاء منهج دراسي يدوي',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'إدخال اسم المنهج والصف والمادة يدوياً وإضافة الدروس لاحقاً',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showManualAddCurriculumDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualAddCurriculumDialog() {
    final nameCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final unitCtrl = TextEditingController();
    final lessonCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedGrade = uniqueGrades.isNotEmpty
        ? uniqueGrades.first
        : 'الصف الأول الثانوي';

    final standardGrades = _sortGrades([
      'الصف الرابع الابتدائي (Prim 4)',
      'الصف الخامس الابتدائي (Prim 5)',
      'الصف السادس الابتدائي (Prim 6)',
      'الصف الأول الإعدادي (Prep 1)',
      'الصف الثاني الإعدادي (Prep 2)',
      'الصف الثالث الإعدادي (Prep 3)',
      'الصف الأول الثانوي (Sec 1)',
      'الصف الثاني الثانوي (Sec 2)',
      'الصف الثالث الثانوي (Sec 3)',
      ...uniqueGrades,
    ]);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.library_books, color: Colors.indigo),
              SizedBox(width: 8),
              Text(
                'إنشاء منهج دراسي يدوي',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المنهج الدراسي',
                    hintText: 'e.g. منهج الصف الأول الإعدادي',
                    prefixIcon: Icon(Icons.menu_book),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: standardGrades.contains(selectedGrade)
                      ? selectedGrade
                      : null,
                  hint: Text(selectedGrade),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'الصف الدراسي',
                    prefixIcon: Icon(Icons.school),
                  ),
                  items: standardGrades
                      .map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) =>
                      setDState(() => selectedGrade = v ?? selectedGrade),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المادة الدراسية',
                    prefixIcon: Icon(Icons.category),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الوحدة الأولى',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lessonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'عنوان أول درس',
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'وصف الدرس / الأهداف (اختياري)',
                    prefixIcon: Icon(Icons.description_outlined),
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
              onPressed: () async {
                final name = nameCtrl.text.trim().isNotEmpty
                    ? nameCtrl.text.trim()
                    : 'منهج $selectedGrade';
                final firstLesson = CurriculumLessonModel(
                  subject: subjectCtrl.text.trim().isNotEmpty
                      ? subjectCtrl.text.trim()
                      : 'عام',
                  grade: selectedGrade,
                  stage: CurriculumExcelService.inferStage(selectedGrade),
                  curriculumName: name,
                  unitName: unitCtrl.text.trim().isNotEmpty
                      ? unitCtrl.text.trim()
                      : 'الوحدة الأولى',
                  lessonTitle: lessonCtrl.text.trim().isNotEmpty
                      ? lessonCtrl.text.trim()
                      : 'الدرس الأول',
                  objectives: descCtrl.text.trim(),
                  chapterNumber: 1,
                  isCompleted: false,
                );
                await widget.database.saveCurriculumLesson(firstLesson);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.green,
                      content: Text('تم إنشاء "$name" بنجاح ✅'),
                    ),
                  );
                }
              },
              child: const Text('إنشاء المنهج'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddLessonDialog({String? prefillGrade, String? prefillCurriculum}) {
    final unitCtrl = TextEditingController();
    final lessonCtrl = TextEditingController();
    final objectivesCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final homeworkCtrl = TextEditingController();
    bool isCompletedVal = false;
    String selectedCurriculum = prefillCurriculum ??
        prefillGrade ??
        (uniqueGrades.isNotEmpty
            ? uniqueGrades.first
            : 'الصف الأول الثانوي (Sec 1)');

    final existingForInitial = _getLessonsForCurriculum(selectedCurriculum);
    final subjectCtrl = TextEditingController(
      text: existingForInitial.isNotEmpty ? existingForInitial.first.subject : 'عام',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.post_add, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text(
                'إضافة درس جديد للمنهج',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: uniqueGrades.contains(selectedCurriculum)
                      ? selectedCurriculum
                      : (uniqueGrades.isNotEmpty ? uniqueGrades.first : null),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'المنهج الدراسي المرتبط',
                    prefixIcon: Icon(Icons.menu_book),
                  ),
                  items: uniqueGrades
                      .map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDState(() {
                        selectedCurriculum = v;
                        final ex = _getLessonsForCurriculum(v);
                        if (ex.isNotEmpty && subjectCtrl.text.trim().isEmpty) {
                          subjectCtrl.text = ex.first.subject;
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المادة الدراسية (Subject)',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الوحدة / الفصل (Unit Name)',
                    hintText: 'e.g. Unit 1: The Role of Technology...',
                    prefixIcon: Icon(Icons.folder),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lessonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'عنوان وموضوع الدرس (Lesson Title)',
                    hintText: 'e.g. Lesson 1: Tools of Scientific Exploration',
                    prefixIcon: Icon(Icons.menu_book),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: objectivesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'وصف الدرس - اختياري (Lesson Description)',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'تم شرح الدرس / مكتمل؟ (Completed? Yes/No)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  value: isCompletedVal,
                  onChanged: (val) => setDState(() => isCompletedVal = val),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'التاريخ - اختياري (Date)',
                          hintText: 'YYYY-MM-DD',
                          prefixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.date_range, color: Colors.indigo),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDState(() {
                            dateCtrl.text = picked.toIso8601String().substring(
                              0,
                              10,
                            );
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: homeworkCtrl,
                  decoration: const InputDecoration(
                    labelText:
                        'ملاحظات المعلم / الواجب (Teacher Notes / Homework)',
                    prefixIcon: Icon(Icons.assignment_outlined),
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
              onPressed: () async {
                if (lessonCtrl.text.trim().isEmpty) return;
                final existingForCur = _getLessonsForCurriculum(selectedCurriculum);
                final derivedGrade = existingForCur.isNotEmpty
                    ? existingForCur.first.grade
                    : selectedCurriculum.replaceFirst(RegExp(r'^منهج\s+'), '').trim();
                final derivedSubject = subjectCtrl.text.trim().isNotEmpty
                    ? subjectCtrl.text.trim()
                    : (existingForCur.isNotEmpty ? existingForCur.first.subject : 'عام');

                final lesson = CurriculumLessonModel(
                  subject: derivedSubject,
                  grade: derivedGrade,
                  stage: CurriculumExcelService.inferStage(derivedGrade),
                  curriculumName: selectedCurriculum,
                  unitName: unitCtrl.text.trim().isNotEmpty
                      ? unitCtrl.text.trim()
                      : 'الوحدة الأولى',
                  lessonTitle: lessonCtrl.text.trim(),
                  objectives: objectivesCtrl.text.trim(),
                  chapterNumber: existingForCur.length + 1,
                  isCompleted: isCompletedVal,
                  lessonDate: dateCtrl.text.trim().isNotEmpty
                      ? dateCtrl.text.trim()
                      : null,
                  homeworkNotes: homeworkCtrl.text.trim().isNotEmpty
                      ? homeworkCtrl.text.trim()
                      : null,
                );
                await widget.database.saveCurriculumLesson(lesson);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.green,
                      content: Text('تمت إضافة الدرس بنجاح ✅'),
                    ),
                  );
                }
              },
              child: const Text('حفظ الدرس'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditLessonDialog(CurriculumLessonModel lesson) {
    final unitCtrl = TextEditingController(text: lesson.unitName);
    final lessonCtrl = TextEditingController(text: lesson.lessonTitle);
    final objectivesCtrl = TextEditingController(text: lesson.objectives);
    final dateCtrl = TextEditingController(text: lesson.lessonDate ?? '');
    final homeworkCtrl = TextEditingController(
      text: lesson.homeworkNotes ?? '',
    );
    bool isCompletedVal = lesson.isCompleted;

    String selectedCurriculum = (lesson.curriculumName ?? '').trim().isNotEmpty
        ? lesson.curriculumName!.trim()
        : (lesson.grade.trim().isNotEmpty
            ? lesson.grade.trim()
            : (uniqueGrades.isNotEmpty
                ? uniqueGrades.first
                : 'الصف الأول الثانوي (Sec 1)'));

    final existingForCur = _getLessonsForCurriculum(selectedCurriculum);
    final subjectCtrl = TextEditingController(
      text: lesson.subject.isNotEmpty && lesson.subject != 'عام'
          ? lesson.subject
          : (existingForCur.isNotEmpty ? existingForCur.first.subject : 'عام'),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.teal),
              SizedBox(width: 8),
              Text(
                'تعديل بيانات الدرس',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: uniqueGrades.contains(selectedCurriculum)
                      ? selectedCurriculum
                      : null,
                  hint: Text(selectedCurriculum),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'المنهج الدراسي',
                    prefixIcon: Icon(Icons.menu_book),
                  ),
                  items: uniqueGrades
                      .map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) =>
                      setDState(() => selectedCurriculum = v ?? selectedCurriculum),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المادة الدراسية (Subject)',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الوحدة / الفصل (Unit Name)',
                    prefixIcon: Icon(Icons.folder),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lessonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'عنوان وموضوع الدرس (Lesson Title)',
                    prefixIcon: Icon(Icons.menu_book),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: objectivesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'وصف الدرس - اختياري (Lesson Description)',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'تم شرح الدرس / مكتمل؟ (Completed? Yes/No)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  value: isCompletedVal,
                  onChanged: (val) => setDState(() => isCompletedVal = val),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'التاريخ - اختياري (Date)',
                          hintText: 'YYYY-MM-DD',
                          prefixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.date_range, color: Colors.indigo),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDState(() {
                            dateCtrl.text = picked.toIso8601String().substring(
                              0,
                              10,
                            );
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: homeworkCtrl,
                  decoration: const InputDecoration(
                    labelText:
                        'ملاحظات المعلم / الواجب (Teacher Notes / Homework)',
                    prefixIcon: Icon(Icons.assignment_outlined),
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
              onPressed: () async {
                if (lessonCtrl.text.trim().isEmpty) return;
                final curLessonsForTarget = _getLessonsForCurriculum(selectedCurriculum);
                final derivedGrade = curLessonsForTarget.isNotEmpty
                    ? curLessonsForTarget.first.grade
                    : (lesson.grade.isNotEmpty
                        ? lesson.grade
                        : selectedCurriculum.replaceFirst(RegExp(r'^منهج\s+'), '').trim());
                final derivedSubject = subjectCtrl.text.trim().isNotEmpty
                    ? subjectCtrl.text.trim()
                    : lesson.subject;

                final updated = lesson.copyWith(
                  curriculumName: selectedCurriculum,
                  grade: derivedGrade,
                  subject: derivedSubject,
                  stage: CurriculumExcelService.inferStage(derivedGrade),
                  unitName: unitCtrl.text.trim().isNotEmpty
                      ? unitCtrl.text.trim()
                      : lesson.unitName,
                  lessonTitle: lessonCtrl.text.trim(),
                  objectives: objectivesCtrl.text.trim(),
                  isCompleted: isCompletedVal,
                  lessonDate: dateCtrl.text.trim().isNotEmpty
                      ? dateCtrl.text.trim()
                      : '',
                  homeworkNotes: homeworkCtrl.text.trim().isNotEmpty
                      ? homeworkCtrl.text.trim()
                      : '',
                );
                await widget.database.saveCurriculumLesson(updated);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.green,
                      content: Text('تم تحديث بيانات الدرس بنجاح ✅'),
                    ),
                  );
                }
              },
              child: const Text('حفظ التعديل'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBindCurriculumToGroupsSheet(String curriculumName, String grade) {
    final boundGroups = _getGroupsBoundTo(curriculumName, grade);
    final selectedGroupIds = boundGroups.map((g) => g.id).toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (c, setSheetState) => Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ربط المنهج: $curriculumName',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Text(
                          'حدد المجموعات التي تدرس هذا المنهج لمتابعة تقدمها التلقائي',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 20),
              if (groups.isEmpty)
                const Center(child: Text('لا توجد مجموعات دراسية مسجلة بعد'))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, i) {
                      final group = groups[i];
                      final isSelected = selectedGroupIds.contains(group.id);

                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isSelected,
                        title: Text(
                          group.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${group.stage} • ${group.grade} • ${group.schedule}',
                        ),
                        secondary: CircleAvatar(
                          backgroundColor: isSelected
                              ? Colors.indigo.withValues(alpha: 0.15)
                              : Colors.grey.shade100,
                          child: Icon(
                            Icons.groups,
                            color: isSelected ? Colors.indigo : Colors.grey,
                          ),
                        ),
                        onChanged: (val) {
                          setSheetState(() {
                            if (val == true) {
                              selectedGroupIds.add(group.id);
                            } else {
                              selectedGroupIds.remove(group.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  for (final g in groups) {
                    if (selectedGroupIds.contains(g.id)) {
                      await widget.database.bindGroupToCurriculum(
                        groupId: g.id,
                        groupName: g.name,
                        grade: g.grade,
                        curriculumName: curriculumName,
                      );
                    } else if (boundGroups.any((bg) => bg.id == g.id)) {
                      await widget.database.unbindGroupFromCurriculum(
                        g.id,
                        groupName: g.name,
                      );
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.green,
                        content: Text(
                          'تم تحديث ربط المجموعات بـ "$curriculumName" بنجاح 🔗',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('تأكيد وحفظ الربط'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EXCEL INTEGRATION: IMPORT & EXPORT CURRICULUM
  // ---------------------------------------------------------------------------
  Future<void> _shareExcelBytes({
    required String fileName,
    required List<int> bytes,
    required String subject,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            name: fileName,
          ),
        ],
        subject: subject,
        text: subject,
      ),
    );
  }

  Future<void> _exportBlankCurriculumTemplate({bool isEnglish = true}) async {
    try {
      final bytes = CurriculumExcelService.createBlankCurriculumTemplateBytes(
        isEnglish: isEnglish,
      );

      await _shareExcelBytes(
        fileName: isEnglish
            ? 'Curriculum_Template_EduAcademy.xlsx'
            : 'نموذج_فارغ_المنهج_الدراسي_EduAcademy.xlsx',
        bytes: bytes,
        subject: isEnglish
            ? 'Curriculum Import Template - Edu Academy'
            : 'نموذج المنهج الدراسي الفارغ للتعبئة - Edu Academy',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('فشل تصدير النموذج: $e'),
          ),
        );
      }
    }
  }

  Future<void> _importCurriculumFromExcel() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (files.isEmpty) return;
      final validFiles = files.where((f) => f.path != null).toList();
      if (validFiles.isEmpty) return;

      // Handle Single File Selection
      if (validFiles.length == 1) {
        final filePath = validFiles.first.path!;
        final fileName = p.basename(filePath);
        final bytes = await File(filePath).readAsBytes();

        final parsedLessons = CurriculumExcelService.parseExcelBytes(
          bytes: bytes,
          fileName: fileName,
        );

        if (parsedLessons.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.orange,
                content: Text(
                  'لم يتم العثور على أي دروس صالحة داخل الملف المختار.',
                ),
              ),
            );
          }
          return;
        }

        final detected = CurriculumExcelService.detectGradeAndCurriculum(
          fileName: fileName,
        );
        final initialCurriculumName = detected['curriculumName']!;
        final initialGrade = detected['grade']!;
        final initialStage = detected['stage']!;
        final initialSubject =
            parsedLessons.first.subject.isNotEmpty &&
                parsedLessons.first.subject != 'عام'
            ? parsedLessons.first.subject
            : 'ICT & تكنولوجيا المعلومات';

        final uniqueUnitsFound = parsedLessons
            .map((l) => l.unitName)
            .toSet()
            .toList();

        if (!mounted) return;

        final confirmed = await _showImportCurriculumPreviewDialog(
          fileName: fileName,
          totalLessons: parsedLessons.length,
          uniqueUnits: uniqueUnitsFound,
          parsedLessons: parsedLessons,
          initialCurriculumName: initialCurriculumName,
          initialGrade: initialGrade,
          initialStage: initialStage,
          initialSubject: initialSubject,
        );

        if (confirmed == null) return;

        setState(() => isLoading = true);

        final updatedLessons = parsedLessons
            .map(
              (l) => l.copyWith(
                curriculumName: confirmed['curriculumName'],
                grade: confirmed['grade'],
                stage: confirmed['stage'],
                subject: confirmed['subject'],
              ),
            )
            .toList();

        await widget.database.saveCurriculumLessonsBatch(
          updatedLessons,
          curriculumName: confirmed['curriculumName'],
        );
        await _loadData();

        if (!mounted) return;

        final report = CurriculumImportReport(
          totalParsed: updatedLessons.length,
          totalSaved: updatedLessons.length,
          grades: [confirmed['grade']!],
          unitsCount: uniqueUnitsFound.length,
        );

        _showCurriculumImportSuccessDialog(report);
        return;
      }

      // Handle Multiple Files Selection
      setState(() => isLoading = true);
      final List<_ParsedCurriculumFile> parsedList = [];

      for (final f in validFiles) {
        final filePath = f.path!;
        final fileName = p.basename(filePath);
        final file = File(filePath);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final lessons = CurriculumExcelService.parseExcelBytes(
          bytes: bytes,
          fileName: fileName,
        );
        if (lessons.isEmpty) continue;

        final detected = CurriculumExcelService.detectGradeAndCurriculum(
          fileName: fileName,
        );
        final uniqueUnits = lessons.map((l) => l.unitName).toSet().toList();
        final sub =
            lessons.first.subject.isNotEmpty && lessons.first.subject != 'عام'
            ? lessons.first.subject
            : 'ICT & تكنولوجيا المعلومات';

        parsedList.add(
          _ParsedCurriculumFile(
            fileName: fileName,
            filePath: filePath,
            lessons: lessons,
            curriculumName: detected['curriculumName']!,
            grade: detected['grade']!,
            stage: detected['stage']!,
            subject: sub,
            uniqueUnits: uniqueUnits,
          ),
        );
      }

      setState(() => isLoading = false);

      if (parsedList.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text(
                'لم يتم العثور على أي دروس صالحة داخل الملفات المختارة.',
              ),
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      final confirmed = await _showMultiFileImportDialog(parsedList);
      if (!confirmed) return;

      setState(() => isLoading = true);

      final allLessonsToSave = <CurriculumLessonModel>[];
      final allGrades = <String>{};
      int totalUnits = 0;

      for (final item in parsedList) {
        allGrades.add(item.grade);
        totalUnits += item.uniqueUnits.length;
        final lessonsForFile = item.lessons
            .map(
              (l) => l.copyWith(
                curriculumName: item.curriculumName,
                grade: item.grade,
                stage: item.stage,
                subject: item.subject,
              ),
            )
            .toList();

        await widget.database.saveCurriculumLessonsBatch(
          lessonsForFile,
          curriculumName: item.curriculumName,
        );
        allLessonsToSave.addAll(lessonsForFile);
      }

      await _loadData();

      if (!mounted) return;

      final report = CurriculumImportReport(
        totalParsed: allLessonsToSave.length,
        totalSaved: allLessonsToSave.length,
        grades: _sortGrades(allGrades),
        unitsCount: totalUnits,
      );

      _showCurriculumImportSuccessDialog(report);
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('حدث خطأ أثناء استيراد المناهج من إكسيل: $e'),
          ),
        );
      }
    }
  }

  Future<bool> _showMultiFileImportDialog(
    List<_ParsedCurriculumFile> parsedFiles,
  ) async {
    final standardGrades = _sortGrades([
      'الصف الرابع الابتدائي (Prim 4)',
      'الصف الخامس الابتدائي (Prim 5)',
      'الصف السادس الابتدائي (Prim 6)',
      'الصف الأول الإعدادي (Prep 1)',
      'الصف الثاني الإعدادي (Prep 2)',
      'الصف الثالث الإعدادي (Prep 3)',
      'الصف الأول الثانوي (Sec 1)',
      'الصف الثاني الثانوي (Sec 2)',
      'الصف الثالث الثانوي (Sec 3)',
      ...uniqueGrades,
    ]);

    int totalLessons = parsedFiles.fold(0, (sum, f) => sum + f.lessons.length);
    int totalUnits = parsedFiles.fold(
      0,
      (sum, f) => sum + f.uniqueUnits.length,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.library_add_check_rounded,
                      color: Color(0xFF10B981),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'استيراد ${parsedFiles.length} مناهج دراسية دفعة واحدة',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'تم التعرف التلقائي على المناهج التالية من الملفات:',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Summary header
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text(
                                'عدد المناهج',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                '${parsedFiles.length}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 24,
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                          Column(
                            children: [
                              const Text(
                                'إجمالي الوحدات',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                '$totalUnits وحدة',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 24,
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                          Column(
                            children: [
                              const Text(
                                'إجمالي الدروس',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                '$totalLessons درساً',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Scrollable list of files
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: parsedFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final item = parsedFiles[idx];
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.menu_book,
                                      size: 18,
                                      color: Colors.indigo,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        item.curriculumName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 17,
                                        color: Colors.blueAccent,
                                      ),
                                      tooltip: 'تعديل بيانات هذا المنهج',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        final editCtrl = TextEditingController(
                                          text: item.curriculumName,
                                        );
                                        String editGrade = item.grade;
                                        final res = await showDialog<bool>(
                                          context: context,
                                          builder: (editCtx) => StatefulBuilder(
                                            builder: (c2, setEditState) => AlertDialog(
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              title: const Text(
                                                'تعديل اسم وصف المنهج',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  TextField(
                                                    controller: editCtrl,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText:
                                                              'اسم المنهج',
                                                        ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  DropdownButtonFormField<
                                                    String
                                                  >(
                                                    initialValue:
                                                        standardGrades.contains(
                                                          editGrade,
                                                        )
                                                        ? editGrade
                                                        : null,
                                                    hint: Text(editGrade),
                                                    isExpanded: true,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText: 'الصف',
                                                        ),
                                                    items: standardGrades
                                                        .map(
                                                          (g) =>
                                                              DropdownMenuItem(
                                                                value: g,
                                                                child: Text(
                                                                  g,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                        )
                                                        .toList(),
                                                    onChanged: (v) {
                                                      if (v != null)
                                                        setEditState(
                                                          () => editGrade = v,
                                                        );
                                                    },
                                                  ),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        editCtx,
                                                        false,
                                                      ),
                                                  child: const Text('إلغاء'),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        editCtx,
                                                        true,
                                                      ),
                                                  child: const Text('حفظ'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                        if (res == true) {
                                          setDState(() {
                                            item.curriculumName = editCtrl.text
                                                .trim();
                                            item.grade = editGrade;
                                            item.stage =
                                                CurriculumExcelService.inferStage(
                                                  editGrade,
                                                );
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item.grade,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${item.lessons.length} درساً • ${item.uniqueUnits.length} وحدات',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      item.fileName,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
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
                    backgroundColor: const Color(0xFF10B981),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    'استيراد جميع المناهج (${parsedFiles.length} مناهج)',
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          );
        },
      ),
    );

    return confirmed == true;
  }

  Future<Map<String, String>?> _showImportCurriculumPreviewDialog({
    required String fileName,
    required int totalLessons,
    required List<String> uniqueUnits,
    required List<CurriculumLessonModel> parsedLessons,
    required String initialCurriculumName,
    required String initialGrade,
    required String initialStage,
    required String initialSubject,
  }) async {
    final nameCtrl = TextEditingController(text: initialCurriculumName);
    final subjectCtrl = TextEditingController(text: initialSubject);
    String selectedGrade = initialGrade;
    String selectedStage = initialStage;
    String selectedTrack = 'لغات';

    final standardGrades = _sortGrades([
      'الصف الرابع الابتدائي (Prim 4)',
      'الصف الخامس الابتدائي (Prim 5)',
      'الصف السادس الابتدائي (Prim 6)',
      'الصف الأول الإعدادي (Prep 1)',
      'الصف الثاني الإعدادي (Prep 2)',
      'الصف الثالث الإعدادي (Prep 3)',
      'الصف الأول الثانوي (Sec 1)',
      'الصف الثاني الثانوي (Sec 2)',
      'الصف الثالث الثانوي (Sec 3)',
      ...uniqueGrades,
    ]);

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.file_download_done_rounded,
                      color: Color(0xFF10B981),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'استيراد منهج دراسي كامل',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'تأكيد وتعديل بيانات المنهج قبل الحفظ',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // File badge & Stats
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF3B82F6,
                          ).withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFF3B82F6,
                            ).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.insert_drive_file_outlined,
                              color: Color(0xFF3B82F6),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'تم اكتشاف: $totalLessons درساً في ${uniqueUnits.length} وحدات دراسية',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Curriculum Name field
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم المنهج الدراسي',
                          hintText: 'e.g. منهج الصف الثاني الإعدادي',
                          prefixIcon: Icon(Icons.menu_book),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Grade dropdown
                      DropdownButtonFormField<String>(
                        initialValue: standardGrades.contains(selectedGrade)
                            ? selectedGrade
                            : null,
                        hint: Text(selectedGrade),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'الصف الدراسي',
                          prefixIcon: Icon(Icons.school),
                        ),
                        items: standardGrades
                            .map(
                              (g) => DropdownMenuItem(
                                value: g,
                                child: Text(
                                  g,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDState(() {
                              selectedGrade = v;
                              selectedStage = CurriculumExcelService.inferStage(
                                v,
                              );
                              if (nameCtrl.text.isEmpty ||
                                  nameCtrl.text.startsWith('منهج')) {
                                nameCtrl.text = 'منهج $v';
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Subject field
                      TextField(
                        controller: subjectCtrl,
                        decoration: const InputDecoration(
                          labelText: 'المادة الدراسية',
                          prefixIcon: Icon(Icons.category),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Track dropdown
                      DropdownButtonFormField<String>(
                        initialValue: selectedTrack,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'المسار التعليمي',
                          prefixIcon: Icon(Icons.language),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'لغات',
                            child: Text(
                              'لغات (Languages)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'عربي',
                            child: Text(
                              'عربي (Arabic)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setDState(() => selectedTrack = v ?? 'لغات'),
                      ),
                      const SizedBox(height: 14),

                      // Preview of discovered units
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'معاينة الوحدات المكتشفة:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '${uniqueUnits.length} وحدات',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: uniqueUnits
                                  .take(6)
                                  .map(
                                    (u) => Chip(
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: EdgeInsets.zero,
                                      labelStyle: const TextStyle(fontSize: 10),
                                      label: Text(
                                        u.length > 25
                                            ? '${u.substring(0, 25)}...'
                                            : u,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            if (uniqueUnits.length > 6)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '+ ${uniqueUnits.length - 6} وحدات أخرى...',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey,
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text('استيراد المنهج كاملاً ($totalLessons درساً)'),
                  onPressed: () {
                    final finalName = nameCtrl.text.trim().isNotEmpty
                        ? nameCtrl.text.trim()
                        : 'منهج $selectedGrade';
                    final finalSubject = subjectCtrl.text.trim().isNotEmpty
                        ? subjectCtrl.text.trim()
                        : 'عام';

                    Navigator.pop(ctx, {
                      'curriculumName': finalName,
                      'grade': selectedGrade,
                      'stage': selectedStage,
                      'subject': finalSubject,
                      'track': selectedTrack,
                    });
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCurriculumImportSuccessDialog(CurriculumImportReport report) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 26,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'تم استيراد المنهج بنجاح',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'إجمالي الدروس المستوردة:',
                          style: TextStyle(fontSize: 13),
                        ),
                        Text(
                          '${report.totalSaved} درساً',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'عدد الوحدات / الأبواب:',
                          style: TextStyle(fontSize: 13),
                        ),
                        Text(
                          '${report.unitsCount} وحدة',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (report.grades.isNotEmpty) ...[
                      const Divider(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'الصفوف: ${report.grades.join(" ، ")}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'تمت إضافة الدروس إلى خطتك الدراسية بنجاح، ويمكنك الآن ربط المجموعات بها ومتابعة تقدم الشرح.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تم وعرض المناهج'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String? actionLabel;
    final IconData actionIcon;
    final VoidCallback? onAction;

    if (_tabController.index == 0) {
      actionLabel = 'إضافة منهج';
      actionIcon = Icons.add_rounded;
      onAction = _showAddCurriculumDialog;
    } else if (_tabController.index == 1) {
      actionLabel = 'ربط مجموعة';
      actionIcon = Icons.link_rounded;
      onAction = groups.isNotEmpty
          ? () => _showChangeGroupCurriculumDialog(groups.first, '')
          : null;
    } else {
      actionLabel = null;
      actionIcon = Icons.add;
      onAction = null;
    }

    return Scaffold(
      appBar: SectionTopBar(
        title: 'خريطة المنهج',
        icon: Icons.menu_book_rounded,
        onBack: widget.onBack,
        actionLabel: actionLabel,
        actionIcon: actionIcon,
        onAction: onAction,
        extraActions: [
          IconButton(
            tooltip: 'مكتبة المذكرات والملفات (PDF) 📚',
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF00F2FE)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeacherMaterialsHubScreen(
                    database: widget.database,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                fontFamily: 'Cairo',
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 12,
                fontFamily: 'Cairo',
              ),
              tabs: [
                const Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.menu_book_rounded, size: 16),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'المناهج',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.groups_rounded, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'المجموعات (${groups.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.history_edu_rounded, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'دفتر الحصص (${sessionLogs.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCurriculaTab(theme, isDark),
                _buildGroupBindingsTab(theme, isDark),
                _buildSessionLogsTab(theme, isDark),
              ],
            ),
    );
  }

  // ==========================================
  // TAB 1: خريطة المناهج والوحدات التفصيلية
  // ==========================================
  Widget _buildCurriculaTab(ThemeData theme, bool isDark) {
    final stages = [
      ('الكل', Icons.all_inclusive_rounded),
      ('المرحلة الابتدائية', Icons.child_care_rounded),
      ('المرحلة الإعدادية', Icons.menu_book_rounded),
      ('الثانوية العامة', Icons.school_rounded),
    ];

    final filteredGrades = uniqueGrades.where((g) {
      if (selectedStageFilter == 'الكل') return true;
      final norm = _normalizeArabicText(g);
      if (selectedStageFilter == 'الثانوية العامة') {
        return norm.contains('ثانوي') || norm.contains('sec');
      }
      if (selectedStageFilter == 'المرحلة الإعدادية') {
        return norm.contains('اعداد') || norm.contains('prep');
      }
      if (selectedStageFilter == 'المرحلة الابتدائية') {
        return norm.contains('ابتدائ') || norm.contains('pri');
      }
      return g.contains(selectedStageFilter);
    }).toList();

    return ListView(
      key: const PageStorageKey<String>('curriculum_list_scroll'),
      padding: const EdgeInsets.all(16),
      children: [
        // Stage Filter Chips Bar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: stages.map((st) {
              final isSel = selectedStageFilter == st.$1;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  avatar: Icon(
                    st.$2,
                    size: 16,
                    color: isSel ? Colors.white : theme.colorScheme.primary,
                  ),
                  label: Text(st.$1),
                  selected: isSel,
                  selectedColor: theme.colorScheme.primary,
                  labelStyle: TextStyle(
                    color: isSel
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (_) {
                    setState(() => selectedStageFilter = st.$1);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        if (isSelectionMode)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إلغاء وضع التحديد',
                    onPressed: _exitSelectionMode,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'تم تحديد ${selectedCurricula.length} من ${filteredGrades.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: Icon(
                      selectedCurricula.length == filteredGrades.length
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 18,
                    ),
                    label: Text(
                      selectedCurricula.length == filteredGrades.length
                          ? 'إلغاء الكل'
                          : 'تحديد الكل',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: () => _toggleSelectAll(filteredGrades),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('حذف (${selectedCurricula.length})'),
                    onPressed: selectedCurricula.isEmpty
                        ? null
                        : () =>
                              _confirmDeleteCurricula(selectedCurricula.toList()),
                  ),
                ],
              ),
            ),
          ),

        if (uniqueGrades.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'لا توجد مناهج دراسية مضافة بعد',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('أضف يدوياً'),
                        onPressed: _showAddCurriculumDialog,
                      ),
                      const SizedBox(width: 10),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('استيراد من Excel'),
                        onPressed: _importCurriculumFromExcel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('تصدير نموذج فارغ لتعبئته في Excel'),
                    onPressed: _exportBlankCurriculumTemplate,
                  ),
                ],
              ),
            ),
          )
        else if (filteredGrades.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 54,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد مناهج مسجلة لـ ($selectedStageFilter)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'يمكنك إضافة منهج جديد مخصص لهذه المرحلة الآن.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text('إضافة منهج لـ $selectedStageFilter'),
                    onPressed: _showAddCurriculumDialog,
                  ),
                ],
              ),
            ),
          )
        else
          ...filteredGrades.map((curriculumKey) {
            final curLessons = _getLessonsForCurriculum(curriculumKey);
            final boundGroups = _getGroupsBoundTo(curriculumKey, curriculumKey);
            final progress = _calculateProgress(curLessons);
            final completedCount = curLessons
                .where((l) => l.isCompleted)
                .length;

            // Group lessons by unit
            final unitsMap = <String, List<CurriculumLessonModel>>{};
            for (final l in curLessons) {
              unitsMap.putIfAbsent(l.unitName, () => []).add(l);
            }
            for (final list in unitsMap.values) {
              list.sort((a, b) {
                final c = a.chapterNumber.compareTo(b.chapterNumber);
                if (c != 0) return c;
                return (a.id ?? 0).compareTo(b.id ?? 0);
              });
            }

            final isSelected = selectedCurricula.contains(curriculumKey);

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: isSelected ? 4 : 1.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: isSelected
                    ? BorderSide(color: theme.colorScheme.primary, width: 2)
                    : BorderSide(
                        color: isDark
                            ? const Color(0xFF334155)
                            : Colors.grey.shade200,
                      ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onLongPress: () {
                  _showCurriculumOptionsMenu(curriculumKey);
                },
                onTap: isSelectionMode
                    ? () => _toggleCurriculumSelected(curriculumKey)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          if (isSelectionMode) ...[
                            Checkbox(
                              value: isSelected,
                              activeColor: theme.colorScheme.primary,
                              onChanged: (_) =>
                                  _toggleCurriculumSelected(curriculumKey),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  curriculumKey,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${unitsMap.length} وحدات • ${curLessons.length} درساً',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${(progress * 100).toStringAsFixed(0)}% مكتمل',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (!isSelectionMode) ...[
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                size: 22,
                                color: Colors.grey,
                              ),
                              tooltip: 'خيارات المنهج',
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              onSelected: (val) {
                                if (val == 'rename') {
                                  _showRenameCurriculumDialog(curriculumKey);
                                } else if (val == 'edit') {
                                  _showEditCurriculumDialog(curriculumKey);
                                } else if (val == 'bind') {
                                  _showBindCurriculumToGroupsSheet(
                                    curriculumKey,
                                    curriculumKey,
                                  );
                                } else if (val == 'delete') {
                                  _confirmDeleteCurricula([curriculumKey]);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.drive_file_rename_outline,
                                        size: 18,
                                        color: Colors.blueAccent,
                                      ),
                                      SizedBox(width: 8),
                                      Text('تسمية المنهج'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.tune_rounded,
                                        size: 18,
                                        color: Colors.teal,
                                      ),
                                      SizedBox(width: 8),
                                      Text('تعديل البيانات'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'bind',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.link,
                                        size: 18,
                                        color: Colors.orange,
                                      ),
                                      SizedBox(width: 8),
                                      Text('ربط المجموعات'),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'حذف المنهج',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          color: progress >= 1.0
                              ? Colors.green
                              : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Bound Groups Info
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(
                            Icons.groups,
                            size: 16,
                            color: Colors.indigo,
                          ),
                          const Text(
                            'المجموعات المرتبطة:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (boundGroups.isEmpty)
                            const Text(
                              'لم تُربط مجموعة بعد',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            )
                          else
                            ...boundGroups.map(
                              (bg) => ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 160),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.indigo.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          bg.name,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.indigo,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _confirmUnbindGroup(
                                          bg,
                                          curriculumKey,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withValues(
                                              alpha: 0.15,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            size: 12,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.link, size: 16),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'ربط بمجموعة 🔗',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              onPressed: () => _showBindCurriculumToGroupsSheet(
                                curriculumKey,
                                curriculumKey,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.add, size: 16),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'إضافة درس ➕',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              onPressed: () => _showAddLessonDialog(
                                prefillGrade: curriculumKey,
                                prefillCurriculum: curriculumKey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),

                      // Units & Lessons Expansion Tree
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            'استعراض ومتابعة إنجاز الدروس ($completedCount من ${curLessons.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          children: unitsMap.entries.map((entry) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.blueGrey.withValues(alpha: 0.2),
                                ),
                              ),
                              child: ExpansionTile(
                                initiallyExpanded: true,
                                leading: const Icon(
                                  Icons.folder_open,
                                  color: Colors.indigo,
                                  size: 20,
                                ),
                                title: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                children: entry.value.map((lesson) {
                                  final hasSub =
                                      lesson.objectives.isNotEmpty ||
                                      (lesson.lessonDate != null &&
                                          lesson.lessonDate!.isNotEmpty) ||
                                      (lesson.homeworkNotes != null &&
                                          lesson.homeworkNotes!.isNotEmpty);

                                  return ListTile(
                                    dense: true,
                                    leading: Checkbox(
                                      value: lesson.isCompleted,
                                      activeColor: const Color(0xFF10B981),
                                      onChanged: (val) async {
                                        if (lesson.id != null) {
                                          await widget.database
                                              .toggleLessonCompleted(
                                                lesson.id!,
                                                val == true,
                                              );
                                          _loadData();
                                        }
                                      },
                                    ),
                                    title: Text(
                                      lesson.lessonTitle,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        decoration: lesson.isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: lesson.isCompleted
                                            ? Colors.grey
                                            : null,
                                      ),
                                    ),
                                    subtitle: hasSub
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (lesson.objectives.isNotEmpty)
                                                Text(
                                                  lesson.objectives,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  if (lesson.lessonDate !=
                                                          null &&
                                                      lesson
                                                          .lessonDate!
                                                          .isNotEmpty) ...[
                                                    const Icon(
                                                      Icons
                                                          .calendar_today_outlined,
                                                      size: 11,
                                                      color: Colors.grey,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      lesson.lessonDate!,
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  if (lesson.homeworkNotes !=
                                                          null &&
                                                      lesson
                                                          .homeworkNotes!
                                                          .isNotEmpty) ...[
                                                    const Icon(
                                                      Icons.assignment_outlined,
                                                      size: 11,
                                                      color: Color(0xFF0D9488),
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Expanded(
                                                      child: Text(
                                                        lesson.homeworkNotes!,
                                                        style: const TextStyle(
                                                          fontSize: 10.5,
                                                          color: Color(
                                                            0xFF0D9488,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          )
                                        : null,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                            color: Colors.blueGrey,
                                          ),
                                          tooltip: 'تعديل بيانات الدرس',
                                          onPressed: () =>
                                              _showEditLessonDialog(lesson),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Colors.redAccent,
                                          ),
                                          tooltip: 'حذف الدرس',
                                          onPressed: () async {
                                            if (lesson.id != null) {
                                              await widget.database
                                                  .deleteCurriculumLesson(
                                                    lesson.id!,
                                                  );
                                              _loadData();
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  // ==========================================
  // TAB 2: ربط المجموعات ومتابعة التقدم
  // ==========================================
  Widget _buildGroupBindingsTab(ThemeData theme, bool isDark) {
    if (groups.isEmpty) {
      return const Center(child: Text('لا توجد مجموعات دراسية مسجلة بعد'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final group = groups[i];
        final binding = groupBindings
            .where((b) => b.groupId == group.id)
            .firstOrNull;
        final isBound =
            binding != null && binding.curriculumName.trim().isNotEmpty;
        final currName = isBound ? binding.curriculumName.trim() : null;
        final curLessons = currName != null
            ? _getLessonsForCurriculum(currName)
            : <CurriculumLessonModel>[];
        final progress = _calculateProgress(curLessons);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${group.stage} • ${group.grade} • ${group.schedule}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isBound)
                          IconButton(
                            icon: const Icon(
                              Icons.link_off_rounded,
                              color: Colors.orange,
                              size: 22,
                            ),
                            tooltip: 'فك ربط المجموعة',
                            onPressed: () =>
                                _confirmUnbindGroup(group, currName!),
                          ),
                        TextButton.icon(
                          icon: Icon(
                            isBound ? Icons.edit_note : Icons.link,
                            size: 18,
                          ),
                          label: Text(
                            isBound ? 'تغيير المنهج' : 'ربط بمنهج',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () => _showChangeGroupCurriculumDialog(
                            group,
                            currName ?? '',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (isBound) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.menu_book,
                          size: 18,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'المنهج المرتبط: $currName',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.indigo,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}% منجز',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      color: progress >= 1.0 ? Colors.green : Colors.indigo,
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.link_off_rounded,
                          size: 18,
                          color: Colors.grey,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'هذه المجموعة غير مرتبطة بأي منهج حالياً',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
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

  void _showChangeGroupCurriculumDialog(
    GroupModel group,
    String currentCurriculum,
  ) async {
    final detailed = await widget.database.getDetailedCurriculaList();
    final customCtrl = TextEditingController();

    String? selected =
        currentCurriculum.isNotEmpty &&
            detailed.any((d) => d['name'] == currentCurriculum)
        ? currentCurriculum
        : null;

    // Smart auto-match if not selected
    if (selected == null && detailed.isNotEmpty) {
      final gGrade = group.grade.trim().toLowerCase();
      for (final d in detailed) {
        final dName = (d['name'] as String? ?? '').toLowerCase();
        final dGrade = (d['grade'] as String? ?? '').toLowerCase();
        if (dGrade.contains(gGrade) ||
            gGrade.contains(dGrade) ||
            dName.contains(gGrade)) {
          selected = d['name'] as String;
          break;
        }
      }
      selected ??= detailed.first['name'] as String;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.link_rounded, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ربط المنهج بـ ${group.name}',
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
                'المرحلة: ${group.stage} • الصف: ${group.grade}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              const Text(
                'اختر المنهج الدراسي من المناهج المستوردة:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: selected,
                hint: const Text('اختر من المناهج المستوردة'),
                isExpanded: true,
                items: detailed.map((d) {
                  final name = d['name'] as String;
                  final lessonsCount =
                      (d['total_lessons'] as num?)?.toInt() ?? 0;
                  final label = lessonsCount > 0
                      ? '$name ($lessonsCount درس)'
                      : name;
                  return DropdownMenuItem(
                    value: name,
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) => setDState(() => selected = v),
              ),
              const SizedBox(height: 12),
              const Text(
                'أو اكتب اسم منهج مخصص جديد (اختياري):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: customCtrl,
                decoration: const InputDecoration(
                  hintText: 'مثال: فيزياء 3 ثانوي لغات',
                  prefixIcon: Icon(Icons.edit_note),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            if (currentCurriculum.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  await widget.database.unbindGroupFromCurriculum(
                    group.id,
                    groupName: group.name,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadData();
                },
                child: const Text('فك الربط'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final target = customCtrl.text.trim().isNotEmpty
                    ? customCtrl.text.trim()
                    : selected;
                if (target == null || target.isEmpty) return;
                await widget.database.bindGroupToCurriculum(
                  groupId: group.id,
                  groupName: group.name,
                  grade: group.grade,
                  curriculumName: target,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadData();
              },
              child: const Text('حفظ الربط'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 3: سجل ودفتر حصص المجموعات
  // ==========================================
  Widget _buildSessionLogsTab(ThemeData theme, bool isDark) {
    if (sessionLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_edu, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            const Text(
              'لا توجد سجلات حصص مسجلة بعد',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'يتم حفظ سجل الحصة تلقائياً عند اعتماد دفتر الحصة اليومي في شاشة الحضور.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sessionLogs.length,
      itemBuilder: (context, i) {
        final log = sessionLogs[i];
        final group = groups.where((g) => g.id == log.groupId).firstOrNull;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
                        group?.name ?? 'مجموعة دراسية',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        log.date,
                        style: const TextStyle(
                          color: Colors.indigo,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '📖 ما تم شرحه: ${log.lessonTitle}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (log.homework.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '📝 الواجب: ${log.homework}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
                if (log.nextTopic.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '🎯 المطلوب للحصة القادمة: ${log.nextTopic}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
