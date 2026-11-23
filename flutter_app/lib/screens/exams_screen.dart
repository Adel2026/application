import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../core/cloud_sync_service.dart';
import '../core/database/database_service.dart';
import '../core/google_forms_sync_service.dart';
import '../core/whatsapp_service.dart';
import '../models/exam_model.dart';
import '../models/group_model.dart';
import '../models/student_model.dart';
import '../widgets/section_top_bar.dart';
import 'certificates_screen.dart';

class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key, required this.database, this.onBack});
  final DatabaseService database;
  final VoidCallback? onBack;

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  bool isLoading = true;
  List<ExamModel> exams = [];
  List<GroupModel> groups = [];
  Map<String, Map<String, double>> examScoresMap = {}; // examId -> {studentId: score}
  Map<String, List<StudentModel>> groupStudentsMap = {}; // groupId -> students

  @override
  void initState() {
    super.initState();
    _loadExamsData();
  }

  Future<void> _loadExamsData() async {
    if (exams.isEmpty && groups.isEmpty) {
      setState(() => isLoading = true);
    }
    final fetchedGroups = await widget.database.getGroups();
    final fetchedExams = await widget.database.getExams();

    final Map<String, Map<String, double>> scoresMap = {};
    for (final exam in fetchedExams) {
      scoresMap[exam.id] = await widget.database.getExamScoresForExam(exam.id);
    }

    final Map<String, List<StudentModel>> gStudents = {};
    for (final group in fetchedGroups) {
      gStudents[group.id] = await widget.database.getStudents(groupId: group.id);
    }

    if (mounted) {
      setState(() {
        groups = fetchedGroups;
        exams = fetchedExams;
        examScoresMap = scoresMap;
        groupStudentsMap = gStudents;
        isLoading = false;
      });
    }
  }

  void _showAddExamDialog() {
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء إضافة مجموعات دراسية أولاً لإنشاء اختبار')),
      );
      return;
    }

    final titleCtrl = TextEditingController();
    final maxScoreCtrl = TextEditingController(text: '50');
    String selectedGroupId = groups.first.id;
    String dateStr = DateTime.now().toIso8601String().substring(0, 10);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                                'إنشاء اختبار / تقييم جديد',
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
                            labelText: 'عنوان الاختبار',
                            prefixIcon: Icon(Icons.assignment_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: selectedGroupId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'المجموعة المستهدفة',
                            prefixIcon: Icon(Icons.groups),
                          ),
                          items: groups
                              .map(
                                (g) => DropdownMenuItem(
                                  value: g.id,
                                  child: Text(
                                    g.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => selectedGroupId = v);
                          },
                        ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: maxScoreCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'الدرجة العظمى', prefixIcon: Icon(Icons.grade)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('تاريخ الاختبار', style: TextStyle(fontSize: 12)),
                            subtitle: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.calendar_today, size: 18),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  dateStr = picked.toIso8601String().substring(0, 10);
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.save),
                      label: const Text('حفظ وبدء رصد الدرجات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        final max = double.tryParse(maxScoreCtrl.text.trim()) ?? 50;
                        if (title.isNotEmpty) {
                          final newExam = ExamModel(
                            id: 'EXAM-${DateTime.now().millisecondsSinceEpoch}',
                            title: title,
                            groupId: selectedGroupId,
                            date: dateStr,
                            maxScore: max,
                          );
                          await widget.database.saveExam(newExam);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          await _loadExamsData();
                          _openScoringSheet(newExam);
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

  void _openScoringSheet(ExamModel exam) {
    final groupStudents = groupStudentsMap[exam.groupId] ?? [];
    final currentScores = Map<String, double>.from(examScoresMap[exam.id] ?? {});

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExamScoringModal(
        exam: exam,
        students: groupStudents,
        initialScores: currentScores,
        database: widget.database,
        onSaved: () {
          _loadExamsData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: SectionTopBar(
        title: 'الاختبارات',
        icon: Icons.assignment_rounded,
        onBack: widget.onBack,
        actionLabel: 'إضافة امتحان',
        actionIcon: Icons.add_rounded,
        onAction: _showAddExamDialog,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 6),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF00F2FE), Color(0xFF0284C7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00F2FE).withValues(alpha: 0.4),
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
                _showAddExamDialog();
              },
              child: const Center(
                child: Icon(
                  Icons.add_rounded,
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
          : exams.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.quiz_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('لم يتم إضافة أي اختبارات بعد', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة أول اختبار الآن'),
                        onPressed: _showAddExamDialog,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24)),
                        label: const Text('معاينة وتصميم شهادات التقدير 🎓', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CertificatesScreen(database: widget.database),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  key: const PageStorageKey<String>('exams_list_scroll'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: exams.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final exam = exams[i];
                    final group = groups.where((g) => g.id == exam.groupId).firstOrNull;
                    final scores = examScoresMap[exam.id] ?? {};
                    final groupStudents = groupStudentsMap[exam.groupId] ?? [];
                    final gradedCount = scores.length;
                    final totalStudents = groupStudents.length;

                    double average = 0;
                    if (scores.isNotEmpty) {
                      average = scores.values.reduce((a, b) => a + b) / scores.length;
                    }

                    return Card(
                      key: ValueKey('exam_card_${exam.id}'),
                      elevation: 0,
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  child: Icon(Icons.quiz, color: Theme.of(context).colorScheme.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        exam.title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      Text(
                                        '${group?.name ?? "مجموعة عامة"} • ${exam.date}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('حذف الاختبار'),
                                        content: Text('هل أنت متأكد من حذف اختبار (${exam.title}) مع كافة درجاته؟'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                          FilledButton(
                                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                            onPressed: () => Navigator.pop(c, true),
                                            child: const Text('حذف'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await widget.database.deleteExam(exam.id);
                                      await CloudSyncService.instance.deleteExamFromCloud(exam.id);
                                      _loadExamsData();
                                    }
                                  },
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            // Metrics row
                            Builder(
                              builder: (ctx) {
                                int eligibleCertCount = 0;
                                if (exam.maxScore > 0 && scores.isNotEmpty) {
                                  for (final sc in scores.values) {
                                    final pct = (sc / exam.maxScore) * 100;
                                    if (pct >= 85) eligibleCertCount++;
                                  }
                                }

                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _StatSmall(label: 'الدرجة العظمى', value: '${exam.maxScore.toStringAsFixed(0)} درجة'),
                                    _StatSmall(label: 'تم رصدهم', value: '$gradedCount / $totalStudents طالب'),
                                    _StatSmall(
                                      label: 'متوسط الدرجات',
                                      value: scores.isNotEmpty ? '${average.toStringAsFixed(1)} / ${exam.maxScore.toStringAsFixed(0)}' : 'لم يُرصد',
                                      color: scores.isNotEmpty ? Colors.blue : Colors.grey,
                                    ),
                                    if (eligibleCertCount > 0)
                                      _StatSmall(
                                        label: 'مستحقي الشهادات',
                                        value: '$eligibleCertCount 🎓',
                                        color: const Color(0xFFF59E0B),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: const Icon(Icons.edit_note),
                                    label: Text(gradedCount > 0 ? 'تعديل الدرجات ($gradedCount)' : 'رصد درجات الطلاب'),
                                    onPressed: () => _openScoringSheet(exam),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.share, color: Color(0xFF25D366)),
                                  label: const Text('إرسال النتائج'),
                                  onPressed: () {
                                    _sendGroupExamResults(exam, groupStudents, scores);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                                  foregroundColor: const Color(0xFFFBBF24),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: const BorderSide(color: Color(0xFFFBBF24), width: 1),
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                ),
                                icon: const Icon(Icons.workspace_premium_rounded, size: 20),
                                label: const Text('شهادات التقدير للمتفوقين 🎓 (جديد)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CertificatesScreen(
                                        database: widget.database,
                                        initialExam: exam,
                                        initialGroup: group,
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
                  },
                ),
    );
  }

  void _sendGroupExamResults(ExamModel exam, List<StudentModel> students, Map<String, double> scores) async {
    if (scores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء رصد الدرجات أولاً قبل الإرسال')),
      );
      return;
    }

    final cName = await widget.database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');

    for (final s in students) {
      final score = scores[s.id];
      if (score != null) {
        final pct = (score / exam.maxScore) * 100;
        final rating = pct >= 85 ? 'ممتاز 🌟' : (pct >= 75 ? 'جيد جداً 👍' : (pct >= 50 ? 'ناجح ✅' : 'يحتاج إلى تحسين ⚠️'));
        final msg = 'السلام عليكم ورحمة الله، ولي أمر الطالب *${s.fullName}*.\nنحيطكم علماً بنتيجة اختبار: *${exam.title}* بتاريخ ${exam.date}.\nالدرجة: *$score من ${exam.maxScore.toStringAsFixed(0)}* (النسبة: ${pct.toStringAsFixed(1)}% - التقدير: $rating).\nإشراف: *$cName* 🌸';
        WhatsAppService.openWhatsApp(phone: s.parentPhone, message: msg);
        break; // Open first for instant dispatch
      }
    }
  }
}

class _StatSmall extends StatelessWidget {
  const _StatSmall({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _ExamScoringModal extends StatefulWidget {
  const _ExamScoringModal({
    required this.exam,
    required this.students,
    required this.initialScores,
    required this.database,
    required this.onSaved,
  });

  final ExamModel exam;
  final List<StudentModel> students;
  final Map<String, double> initialScores;
  final DatabaseService database;
  final VoidCallback onSaved;

  @override
  State<_ExamScoringModal> createState() => _ExamScoringModalState();
}

class _ExamScoringModalState extends State<_ExamScoringModal> {
  late Map<String, TextEditingController> _controllers;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    for (final s in widget.students) {
      final existingScore = widget.initialScores[s.id];
      _controllers[s.id] = TextEditingController(
        text: existingScore != null ? existingScore.toStringAsFixed(0) : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveScores() async {
    setState(() => isSaving = true);
    final Map<String, double> scoresToSave = {};
    for (final entry in _controllers.entries) {
      final val = double.tryParse(entry.value.text.trim());
      if (val != null) {
        scoresToSave[entry.key] = val.clamp(0.0, widget.exam.maxScore);
      }
    }

    await widget.database.recordExamScoresBatch(widget.exam.id, scoresToSave);

    // مزامنة فورية ومباشرة لدرجات هذا الاختبار وترحيلها لتطبيق الطالب فوراً
    try {
      await CloudSyncService.instance.syncExamScoresDirect(
        examId: widget.exam.id,
        examTitle: widget.exam.title,
        maxScore: widget.exam.maxScore,
        examDate: widget.exam.date,
        scores: scoresToSave,
      );
      // تشغيل مزامنة شاملة في الخلفية لتحديث الرتب العامة
      CloudSyncService.instance.syncExams();
    } catch (e) {
      debugPrint('Cloud sync error on save exam: $e');
    }

    // Trigger auto WhatsApp send if enabled
    for (final entry in scoresToSave.entries) {
      final s = widget.students.where((st) => st.id == entry.key).firstOrNull;
      if (s != null && s.parentPhone.isNotEmpty) {
        WhatsAppService.autoSendExamScore(
          database: widget.database,
          studentName: s.fullName,
          parentPhone: s.parentPhone,
          examTitle: widget.exam.title,
          score: entry.value,
          maxScore: widget.exam.maxScore,
        );
      }
    }

    if (!mounted) return;
    setState(() => isSaving = false);
    Navigator.pop(context);
    widget.onSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: const Color(0xFF10B981), content: Text('تم حفظ ورصد درجات (${scoresToSave.length}) طالب وترحيلها لتطبيق الطالب بنجاح 💾🚀')),
    );
  }

  void _openGoogleFormsSyncSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GoogleFormsSyncModal(
        students: widget.students,
        onScoresMatched: _applyScores,
      ),
    );
  }

  void _applyScores(GoogleFormsSyncResult result) {
    int updatedCount = 0;
    setState(() {
      for (final entry in result.matchedScores.entries) {
        final ctrl = _controllers[entry.key];
        if (ctrl != null) {
          ctrl.text = entry.value % 1 == 0
              ? entry.value.toInt().toString()
              : entry.value.toString();
          updatedCount++;
        }
      }
    });

    if (result.unmatchedRecordNames.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('نتائج المطابقة السحابية', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '✅ تم مطابقة ورصد درجات ($updatedCount) طالب بنجاح.',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                ),
                const SizedBox(height: 12),
                const Text(
                  '⚠️ الأسماء التالية وُجدت في نتائج نموذج Google ولكن لم تُطابق أسماء طلاب هذه المجموعة:',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: result.unmatchedRecordNames.take(15).map((n) => Text('• $n', style: const TextStyle(fontSize: 11.5))).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً، فهمت'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF059669),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم بنجاح سحب ومطابقة درجات ($updatedCount) طالب سحابياً ☁️',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.exam.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'الدرجة العظمى: ${widget.exam.maxScore.toStringAsFixed(0)} • عدد الطلاب: ${widget.students.length}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4).withValues(alpha: 0.12),
                      foregroundColor: const Color(0xFF1A73E8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.cloud_sync_rounded, size: 20),
                    label: const Text(
                      'سحب الدرجات سحابياً من Google Form / Sheets ☁️',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _openGoogleFormsSyncSheet,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: widget.students.isEmpty
                ? Center(
                    child: Text('لا يوجد طلاب مسجلين في هذه المجموعة', style: TextStyle(color: Colors.grey.shade600)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.students.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final student = widget.students[i];
                      final ctrl = _controllers[student.id]!;
                      final scoreVal = double.tryParse(ctrl.text);
                      final pct = scoreVal != null ? (scoreVal / widget.exam.maxScore) * 100 : null;

                      return Card(
                        elevation: 0,
                        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(student.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    if (pct != null)
                                      Text(
                                        '${pct.toStringAsFixed(0)}% • ${pct >= 85 ? "ممتاز" : (pct >= 50 ? "ناجح" : "راسب")}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: pct >= 85 ? Colors.green : (pct >= 50 ? Colors.blue : Colors.red),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Score Input
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: ctrl,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    hintText: '/ ${widget.exam.maxScore.toStringAsFixed(0)}',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // WhatsApp Single Dispatch
                              IconButton(
                                icon: const Icon(Icons.share, color: Color(0xFF25D366), size: 20),
                                tooltip: 'إرسال لولي الأمر واتساب',
                                onPressed: () async {
                                  final sVal = double.tryParse(ctrl.text);
                                  if (sVal != null) {
                                    final pVal = (sVal / widget.exam.maxScore) * 100;
                                    final cName = await widget.database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
                                    final msg = 'السلام عليكم ورحمة الله، ولي أمر الطالب *${student.fullName}*.\nنتيجة اختبار *${widget.exam.title}*:\nالدرجة: *$sVal من ${widget.exam.maxScore.toStringAsFixed(0)}* (${pVal.toStringAsFixed(1)}%).\nإشراف: *$cName* 🌸';
                                    WhatsAppService.openWhatsApp(phone: student.parentPhone, message: msg);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
              label: const Text('حفظ كافة الدرجات 💾', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: isSaving ? null : _saveScores,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleFormsSyncModal extends StatefulWidget {
  const _GoogleFormsSyncModal({
    required this.students,
    required this.onScoresMatched,
  });

  final List<StudentModel> students;
  final Function(GoogleFormsSyncResult result) onScoresMatched;

  @override
  State<_GoogleFormsSyncModal> createState() => _GoogleFormsSyncModalState();
}

class _GoogleFormsSyncModalState extends State<_GoogleFormsSyncModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _urlController = TextEditingController();
  final _pasteController = TextEditingController();

  bool _isCheckingAuth = true;
  bool _isSignedIn = false;
  String? _userEmail;
  bool _isLoadingDrive = false;
  List<GoogleFormSheetItem> _driveItems = [];
  String? _driveError;

  bool _isProcessingLink = false;
  bool _isProcessingFile = false;
  bool _isProcessingPaste = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _checkGoogleAuth();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _checkGoogleAuth() async {
    setState(() => _isCheckingAuth = true);
    try {
      final signedIn = await GoogleFormsSyncService.isSignedIn();
      final user = GoogleFormsSyncService.currentUser;
      setState(() {
        _isSignedIn = signedIn;
        _userEmail = user?.email;
        _isCheckingAuth = false;
      });

      if (signedIn) {
        _loadDriveFiles();
      }
    } catch (_) {
      setState(() => _isCheckingAuth = false);
    }
  }

  Future<void> _signInGoogle() async {
    setState(() {
      _isLoadingDrive = true;
      _driveError = null;
    });
    try {
      final account = await GoogleFormsSyncService.signIn();
      if (account != null) {
        setState(() {
          _isSignedIn = true;
          _userEmail = account.email;
        });
        await _loadDriveFiles();
      } else {
        setState(() => _isLoadingDrive = false);
      }
    } catch (e) {
      String msg = 'تعذر تسجيل الدخول: $e';
      if (e.toString().contains('10') || e.toString().contains('sign_in_failed')) {
        msg =
            'تعذر الاتصال المباشر عبر Google Play Services (رمز 10: يتطلب إعداد OAuth في Google Cloud Console لهذا التطبيق).\n\n💡 يُرجى استخدام تبويب "رابط مباشر" أو "ملف Excel/CSV" حيث يعملان فوراً وبكفاءة 100% دون الحاجة لأي إعدادات.';
      }
      setState(() {
        _isLoadingDrive = false;
        _driveError = msg;
      });
    }
  }

  Future<void> _loadDriveFiles() async {
    setState(() {
      _isLoadingDrive = true;
      _driveError = null;
    });

    try {
      final items = await GoogleFormsSyncService.listFormsAndSheets();
      setState(() {
        _driveItems = items;
        _isLoadingDrive = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingDrive = false;
        _driveError = e.toString();
      });
    }
  }

  Future<void> _importFromDriveItem(GoogleFormSheetItem item) async {
    setState(() => _isLoadingDrive = true);
    try {
      final csv = await GoogleFormsSyncService.fetchCsvFromDrive(item.id);
      final result = GoogleFormsSyncService.parseAndMatchScores(
        csvContent: csv,
        students: widget.students,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onScoresMatched(result);
      }
    } catch (e) {
      setState(() => _isLoadingDrive = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('تعذر قراءة النموذج: $e'),
          ),
        );
      }
    }
  }

  Future<void> _importFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء إدخال رابط Google Sheet أولاً')),
      );
      return;
    }

    setState(() => _isProcessingLink = true);
    try {
      final csv = await GoogleFormsSyncService.fetchCsvFromLink(url);
      final result = GoogleFormsSyncService.parseAndMatchScores(
        csvContent: csv,
        students: widget.students,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onScoresMatched(result);
      }
    } catch (e) {
      setState(() => _isProcessingLink = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Text('تنبيه بخصوص الرابط', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Text(
              '$e',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً، فهمت'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('استيراد كملف Excel بدلاً من ذلك'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _tabController.animateTo(1);
                },
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _importFromFile() async {
    setState(() => _isProcessingFile = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (files.isEmpty || files.first.path == null) {
        setState(() => _isProcessingFile = false);
        return;
      }

      final filePath = files.first.path!;
      final bytes = await File(filePath).readAsBytes();

      final result = GoogleFormsSyncService.parseExcelOrCsvBytes(
        bytes: bytes,
        students: widget.students,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onScoresMatched(result);
      }
    } catch (e) {
      setState(() => _isProcessingFile = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('تعذر قراءة الملف: $e'),
          ),
        );
      }
    }
  }

  Future<void> _importFromPastedText() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى لصق بيانات أو أعمدة الجدول أولاً')),
      );
      return;
    }

    setState(() => _isProcessingPaste = true);
    try {
      final result = GoogleFormsSyncService.parseTextAndMatchScores(
        text: text,
        students: widget.students,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onScoresMatched(result);
      }
    } catch (e) {
      setState(() => _isProcessingPaste = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('تعذر معالجة النص: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cloud_download_rounded,
                      color: Color(0xFF1A73E8), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سحب نتائج الاختبار سحابياً ☁️',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'رصد تلقائي فوري ومطابقة ذكية مع قائمة طلاب المجموعة',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF1A73E8),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF1A73E8),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(
                  icon: Icon(Icons.link_rounded, size: 18),
                  text: 'رابط مباشر'),
              Tab(
                  icon: Icon(Icons.upload_file_rounded, size: 18),
                  text: 'ملف Excel / CSV'),
              Tab(
                  icon: Icon(Icons.paste_rounded, size: 18),
                  text: 'لصق نصي'),
              Tab(
                  icon: Icon(Icons.cloud_rounded, size: 18),
                  text: 'Google Drive'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Direct Link (Default)
                _buildDirectLinkTab(isDark),

                // Tab 2: File Picker (Excel / CSV)
                _buildFileImportTab(isDark),

                // Tab 3: Paste Text
                _buildPasteTextTab(isDark),

                // Tab 4: Google Cloud Drive
                _buildGoogleDriveTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectLinkTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    color: Color(0xFF0284C7), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سحب فوري بدون الحاجة لتسجيل دخول',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'افتح جدول النتائج (Google Sheets) في متصفحك أو تطبيق Drive، وانسخ رابطه وألصقه هنا.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('رابط Google Sheet للنتائج:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'https://docs.google.com/spreadsheets/d/...',
              hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste_rounded),
                tooltip: 'لصق من الحافظة',
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null && data!.text!.isNotEmpty) {
                    _urlController.text = data.text!.trim();
                  }
                },
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Color(0xFF10B981), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'خطوات الحصول على الرابط الصحيح:',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.grey.shade200 : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '1. إذا كان لديك Google Form: افتح النموذج، اضغط تبويب "الردود (Responses)"، ثم اضغط أيقونة Google Sheets الخضراء لفتح جدول الردود.\n'
                  '2. اضغط على زر "مشاركة (Share)" في أعلى الشيت، وتأكد من اختيار: "أي شخص لديه الرابط يمكنه العرض".\n'
                  '3. انسخ رابط الشيت والصقه في الحقل أعلاه.',
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: const Color(0xFF1A73E8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isProcessingLink
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.cloud_download_rounded),
            label: const Text('سحب ومطابقة درجات الطلاب فوراً ⚡',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            onPressed: _isProcessingLink ? null : _importFromUrl,
          ),
        ],
      ),
    );
  }

  Widget _buildFileImportTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.file_present_rounded,
                size: 50, color: Color(0xFF10B981)),
          ),
          const SizedBox(height: 16),
          const Text(
            'استيراد ملف Excel أو CSV من جهازك 📂',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'يمكنك تنزيل شيت النتائج من Google Forms أو Google Sheets كملف (Excel .xlsx أو .csv) واختياره مباشرة من الهاتف أو من تطبيق Google Drive بدون أي قيود.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.3),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: Color(0xFF10B981), size: 16),
                    SizedBox(width: 6),
                    Text(
                      'الملفات المدعومة تلقائياً:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  '• ملفات مايكروسوفت إكسيل (.xlsx / .xls)\n'
                  '• ملفات جداول البيانات المفصولة بفواصل (.csv)\n'
                  '• يتم التعرف تلقائياً على أعمدة الأسماء، الدرجات، وأرقام الهواتف.',
                  style: TextStyle(fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isProcessingFile
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.file_upload_rounded),
            label: const Text('اختيار ملف النتائج من الهاتف / Drive 🚀',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            onPressed: _isProcessingFile ? null : _importFromFile,
          ),
        ],
      ),
    );
  }

  Widget _buildPasteTextTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.content_paste_go_rounded,
                    color: Color(0xFFF59E0B), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'لصق مباشر لبيانات الجدول',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'انسخ أعمدة الأسماء والدرجات مباشرة من Google Sheets أو WhatsApp أو Excel وألصقها هنا.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('البيانات المنسوخة:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              TextButton.icon(
                icon: const Icon(Icons.content_paste_rounded, size: 16),
                label: const Text('لصق من الحافظة'),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null && data!.text!.isNotEmpty) {
                    _pasteController.text = data.text!.trim();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _pasteController,
            maxLines: 7,
            decoration: InputDecoration(
              hintText: 'مثال:\nأحمد محمد\t18\nسارة علي\t20\nمحمد حسن\t15',
              hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isProcessingPaste
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.flash_on_rounded),
            label: const Text('معالجة ومطابقة الدرجات فوراً ⚡',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            onPressed: _isProcessingPaste ? null : _importFromPastedText,
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleDriveTab(bool isDark) {
    if (_isCheckingAuth) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (!_isSignedIn) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_circle_outlined,
                  size: 54, color: Color(0xFF4285F4)),
            ),
            const SizedBox(height: 18),
            const Text(
              'الربط المباشر بحساب Google Drive',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'سجّل الدخول بحساب Google لعرض نماذج اختباراتك وجداول الردود على Google Drive وسحب النتائج بنقرة واحدة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            if (_driveError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.amber.shade700.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _driveError!,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isLoadingDrive
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.login_rounded),
              label: const Text('تسجيل الدخول بحساب Google 🚀',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _isLoadingDrive ? null : _signInGoogle,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('استخدام الرابط المباشر بدلاً من ذلك'),
              onPressed: () => _tabController.animateTo(0),
            ),
          ],
        ),
      );
    }

    // Signed in
    return Column(
      children: [
        // User Info bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _userEmail ?? 'تم تسجيل الدخول بنجاح',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'تحديث النماذج',
                onPressed: _isLoadingDrive ? null : _loadDriveFiles,
              ),
            ],
          ),
        ),

        // Files List
        Expanded(
          child: _isLoadingDrive
              ? const Center(child: CircularProgressIndicator.adaptive())
              : (_driveError != null)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Colors.amber, size: 40),
                            const SizedBox(height: 10),
                            Text(_driveError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('إعادة المحاولة'),
                              onPressed: _loadDriveFiles,
                            ),
                          ],
                        ),
                      ),
                    )
                  : (_driveItems.isEmpty)
                      ? Center(
                          child: Text(
                            'لم يتم العثور على نماذج أو جداول Google في حسابك',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: _driveItems.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final item = _driveItems[idx];
                            return ListTile(
                              tileColor: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF8FAFC),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (item.isForm
                                          ? const Color(0xFF7248B9)
                                          : const Color(0xFF0F9D58))
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  item.isForm
                                      ? Icons.assignment_rounded
                                      : Icons.table_chart_rounded,
                                  color: item.isForm
                                      ? const Color(0xFF7248B9)
                                      : const Color(0xFF0F9D58),
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                item.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                item.isForm
                                    ? 'نموذج Google Forms'
                                    : 'جدول نتائج Google Sheets',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                              trailing: FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('سحب النتائج ⚡',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                                onPressed: () => _importFromDriveItem(item),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

