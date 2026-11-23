import 'package:flutter/material.dart';
import '../core/academy_communication_service.dart';
import '../core/database/database_service.dart';

class TeacherBroadcastScreen extends StatefulWidget {
  final DatabaseService database;

  const TeacherBroadcastScreen({super.key, required this.database});

  @override
  State<TeacherBroadcastScreen> createState() => _TeacherBroadcastScreenState();
}

class _TeacherBroadcastScreenState extends State<TeacherBroadcastScreen> {
  final _service = AcademyCommunicationService.instance;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _students = [];
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadGroupsAndStudents();
  }

  Future<void> _loadGroupsAndStudents() async {
    try {
      final db = await widget.database.database;
      final g = await db.query('groups', columns: ['id', 'name']);
      final s = await db.query('students', columns: ['id', 'full_name']);
      if (mounted) {
        setState(() {
          _groups = g;
          _students = s;
          _isLoadingData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  void _openCreateNotificationDialog() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String selectedType = 'general';
    String targetType = 'all'; // all, group, student
    String? selectedTargetId;
    String selectedTargetName = 'جميع الطلاب';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
          final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 24,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.campaign_rounded, color: Color(0xFF00B4D8), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'إرسال إشعار / تنبيه للطلاب 📢',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Target Selector
                  const Text('الجهة المستهدفة:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('الكل 👥')),
                      ButtonSegment(value: 'group', label: Text('مجموعة 🏫')),
                      ButtonSegment(value: 'student', label: Text('طالب 🎓')),
                    ],
                    selected: {targetType},
                    onSelectionChanged: (val) {
                      setModalState(() {
                        targetType = val.first;
                        selectedTargetId = null;
                        if (targetType == 'all') {
                          selectedTargetName = 'جميع الطلاب';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  if (targetType == 'group') ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedTargetId,
                      decoration: InputDecoration(
                        labelText: 'اختر المجموعة المستهدفة',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _groups.map((g) {
                        return DropdownMenuItem(
                          value: '${g['id']}',
                          child: Text('${g['name']}'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setModalState(() {
                          selectedTargetId = val;
                          final match = _groups.firstWhere((g) => '${g['id']}' == val, orElse: () => {});
                          selectedTargetName = 'مجموعة ${match['name'] ?? ''}';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (targetType == 'student') ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedTargetId,
                      decoration: InputDecoration(
                        labelText: 'اختر الطالب المستهدف',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _students.map((s) {
                        return DropdownMenuItem(
                          value: '${s['id']}',
                          child: Text('${s['full_name']}'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setModalState(() {
                          selectedTargetId = val;
                          final match = _students.firstWhere((s) => '${s['id']}' == val, orElse: () => {});
                          selectedTargetName = 'الطالب ${match['full_name'] ?? ''}';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Type Chips
                  const Text('نوع الإشعار:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildTypeChip('عام 📌', 'general', selectedType, (t) => setModalState(() => selectedType = t)),
                      _buildTypeChip('حصة / موعد ⏰', 'session', selectedType, (t) => setModalState(() => selectedType = t)),
                      _buildTypeChip('اختبار 📝', 'exam', selectedType, (t) => setModalState(() => selectedType = t)),
                      _buildTypeChip('مالي 🧾', 'financial', selectedType, (t) => setModalState(() => selectedType = t)),
                      _buildTypeChip('عاجل 🚨', 'urgent', selectedType, (t) => setModalState(() => selectedType = t)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Title Input
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'عنوان الإشعار',
                      hintText: 'مثال: تنبيه بخصوص موعد الحصة القادمة',
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Body Input
                  TextField(
                    controller: bodyController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'نص الرسالة / التنبيه',
                      hintText: 'اكتب نص التنبيه الموجه للطلاب وأولياء الأمور...',
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 18),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B4D8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('بث الإشعار الآن للطلاب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: () async {
                      if (titleController.text.trim().isEmpty || bodyController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى كتابة عنوان ونص الإشعار')),
                        );
                        return;
                      }

                      Navigator.pop(ctx);
                      try {
                        await _service.sendNotification(
                          title: titleController.text,
                          body: bodyController.text,
                          type: selectedType,
                          targetType: targetType,
                          targetId: selectedTargetId ?? 'all',
                          targetName: selectedTargetName,
                        );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF10B981),
                              content: Text('✅ تم بث الإشعار لحظياً لجميع الطلاب المعنيين!'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تعذر الإرسال: $e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTypeChip(String label, String value, String currentVal, Function(String) onSelect) {
    final isSelected = value == currentVal;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelect(value),
      selectedColor: const Color(0xFF00F2FE).withValues(alpha: 0.25),
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إشعارات وتنبيهات الطلاب 📢'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00B4D8),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('إرسال إشعار جديد', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _openCreateNotificationDialog,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _service.streamAllNotifications(),
        builder: (context, snapshot) {
          if (_isLoadingData || snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final list = snapshot.data ?? [];
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade500),
                  const SizedBox(height: 12),
                  const Text(
                    'لا توجد إشعارات مرسلة حالياً',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'اضغط على الزر بالأسفل لإرسال تنبيه أو إعلان لحظي للطلاب',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16).copyWith(bottom: 80),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final notif = list[index];
              final id = notif['id'] ?? '';
              final title = notif['title'] ?? '';
              final body = notif['body'] ?? '';
              final type = notif['type'] ?? 'general';
              final targetName = notif['target_name'] ?? 'الكل';

              Color typeColor;
              IconData typeIcon;
              switch (type) {
                case 'urgent':
                  typeColor = Colors.red;
                  typeIcon = Icons.warning_rounded;
                  break;
                case 'session':
                  typeColor = Colors.orange;
                  typeIcon = Icons.event_available_rounded;
                  break;
                case 'exam':
                  typeColor = Colors.purple;
                  typeIcon = Icons.quiz_rounded;
                  break;
                case 'financial':
                  typeColor = Colors.green;
                  typeIcon = Icons.payments_rounded;
                  break;
                default:
                  typeColor = const Color(0xFF00B4D8);
                  typeIcon = Icons.campaign_rounded;
              }

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(typeIcon, color: typeColor, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'المستهدف: $targetName',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                            tooltip: 'حذف الإشعار',
                            onPressed: () => _service.deleteNotification(id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
