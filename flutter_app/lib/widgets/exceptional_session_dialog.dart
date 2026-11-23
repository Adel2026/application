import 'package:flutter/material.dart';

import '../core/database/database_service.dart';
import '../core/schedule_conflict_service.dart';
import '../models/exceptional_session_model.dart';
import '../models/group_model.dart';

String formatTimeOfDayTo12Hour(TimeOfDay time) {
  final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.period == DayPeriod.am ? 'AM' : 'PM';
  return '${hour.toString().padLeft(2, '0')}:$minute $period';
}

String getArabicDayName(DateTime date) {
  switch (date.weekday) {
    case DateTime.saturday:
      return 'السبت';
    case DateTime.sunday:
      return 'الأحد';
    case DateTime.monday:
      return 'الاثنين';
    case DateTime.tuesday:
      return 'الثلاثاء';
    case DateTime.wednesday:
      return 'الأربعاء';
    case DateTime.thursday:
      return 'الخميس';
    case DateTime.friday:
      return 'الجمعة';
    default:
      return '';
  }
}

Future<void> showAddExceptionalSessionDialog({
  required BuildContext context,
  required DatabaseService database,
  List<GroupModel>? allGroups,
  GroupModel? preselectedGroup,
  String initialReason = 'teacher_makeup',
  String? initialNotes,
  DateTime? initialDate,
  VoidCallback? onSaved,
}) async {
  final groups = allGroups ?? await database.getGroups();
  if (!context.mounted) return;
  if (groups.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('يرجى إنشاء مجموعة دراسية أولاً قبل جدولة حصة استثنائية'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  String selectedGroupId = preselectedGroup?.id ?? groups.first.id;
  String selectedReason = initialReason;
  String selectedScale = 'single'; // 'single' or 'double'
  DateTime selectedDate = initialDate ?? DateTime.now();
  TimeOfDay selectedTime = const TimeOfDay(hour: 16, minute: 0);
  bool isRecurring = false;
  final notesCtrl = TextEditingController(text: initialNotes ?? '');

  final reasons = [
    {'key': 'teacher_makeup', 'label': 'تعويض (إلغاء المدرس)', 'icon': Icons.person_off_rounded, 'color': const Color(0xFFF59E0B)},
    {'key': 'student_makeup', 'label': 'تعويض (غياب/إلغاء الطالب)', 'icon': Icons.swap_horiz_rounded, 'color': const Color(0xFF0284C7)},
    {'key': 'curriculum', 'label': 'استكمال المنهج', 'icon': Icons.menu_book_rounded, 'color': const Color(0xFF10B981)},
    {'key': 'revision', 'label': 'مراجعة ليلة الامتحان', 'icon': Icons.quiz_rounded, 'color': const Color(0xFF8B5CF6)},
    {'key': 'custom', 'label': 'حصة إضافية مخصصة', 'icon': Icons.star_rounded, 'color': const Color(0xFFEC4899)},
  ];

  final exceptionalSessions = await database.getExceptionalSessions();

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final isDark = Theme.of(modalCtx).brightness == Brightness.dark;
          final theme = Theme.of(modalCtx);
          final dayName = getArabicDayName(selectedDate);
          final dateStr =
              '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

          final targetGroup = groups.firstWhere(
            (g) => g.id == selectedGroupId,
            orElse: () => groups.first,
          );

          // فحص تعارض المواعيد الحي للحصة الاستثنائية
          final currentConflicts =
              ScheduleConflictService.checkProposedExceptionalSessionConflicts(
                targetGroupId: targetGroup.id,
                targetGroupName: targetGroup.name,
                proposedDate: dateStr,
                proposedDay: dayName,
                proposedTime: formatTimeOfDayTo12Hour(selectedTime),
                proposedScale: selectedScale,
                allGroups: groups,
                exceptionalSessions: exceptionalSessions,
              );

          return AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 24),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'جدولة حصة استثنائية / تعويضية',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
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
                    // 1. اختيار المجموعة
                    const Text('المجموعة المستهدفة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedGroupId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      ),
                      items: groups.map((g) {
                        return DropdownMenuItem(
                          value: g.id,
                          child: Text(
                            g.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => selectedGroupId = v);
                      },
                    ),
                    const SizedBox(height: 14),

                    // 2. سبب الحصة الاستثنائية
                    const Text('سبب / هدف الحصة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: reasons.map((r) {
                        final isSelected = selectedReason == r['key'];
                        final rColor = r['color'] as Color;
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(r['icon'] as IconData, size: 14, color: isSelected ? Colors.white : rColor),
                              const SizedBox(width: 4),
                              Text(
                                r['label'] as String,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                ),
                              ),
                            ],
                          ),
                          selected: isSelected,
                          selectedColor: rColor,
                          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          onSelected: (_) => setModalState(() => selectedReason = r['key'] as String),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // 3. نوع الحصة: فردية (1x) أو دوبل (2x)
                    const Text('حجم الحصة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setModalState(() => selectedScale = 'single'),
                              borderRadius: BorderRadius.circular(9),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: selectedScale == 'single'
                                      ? (isDark ? theme.colorScheme.primary : Colors.white)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                  boxShadow: selectedScale == 'single'
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.08),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    'حصة فردية (1x)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selectedScale == 'single' ? FontWeight.bold : FontWeight.w500,
                                      color: selectedScale == 'single'
                                          ? (isDark ? Colors.white : theme.colorScheme.primary)
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: InkWell(
                              onTap: () => setModalState(() => selectedScale = 'double'),
                              borderRadius: BorderRadius.circular(9),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: selectedScale == 'double' ? Colors.amber.shade700 : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                  boxShadow: selectedScale == 'double'
                                      ? [
                                          BoxShadow(
                                            color: Colors.amber.shade900.withValues(alpha: 0.3),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.bolt,
                                        size: 15,
                                        color: selectedScale == 'double' ? Colors.white : Colors.amber.shade800,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'حصة دوبل (2x)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: selectedScale == 'double' ? FontWeight.bold : FontWeight.w500,
                                          color: selectedScale == 'double' ? Colors.white : Colors.amber.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 4. التاريخ والوقت
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: modalCtx,
                                initialDate: selectedDate,
                                firstDate: DateTime.now().subtract(const Duration(days: 7)),
                                lastDate: DateTime.now().add(const Duration(days: 90)),
                              );
                              if (picked != null) {
                                setModalState(() => selectedDate = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('التاريخ واليوم:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.amber),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '$dayName ($dateStr)',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: modalCtx,
                                initialTime: selectedTime,
                              );
                              if (picked != null) {
                                setModalState(() => selectedTime = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('وقت الحصة:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time_rounded, size: 14, color: Colors.amber),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          formatTimeOfDayTo12Hour(selectedTime),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 5. التكرار الأسبوعي
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تتكرر أسبوعياً؟', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                        isRecurring ? 'نعم، تتكرر كل أسبوع في نفس اليوم والوقت' : 'لا، حصة لمرة واحدة فقط',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      value: isRecurring,
                      onChanged: (v) => setModalState(() => isRecurring = v),
                    ),
                    const SizedBox(height: 6),

                    // 6. ملاحظات
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'ملاحظات إضافية عن الحصة (اختياري)...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      ),
                    ),

                    // تنبيه تعارض المواعيد المباشر للحصة الاستثنائية
                    if (currentConflicts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ScheduleConflictService.buildConflictWarningBanner(
                        conflicts: currentConflicts,
                        context: modalCtx,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.end,
            actionsOverflowButtonSpacing: 8,
            actionsOverflowDirection: VerticalDirection.down,
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(modalCtx),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: const Text('جدولة الحصة الآن', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  if (currentConflicts.isNotEmpty) {
                    final proceed =
                        await ScheduleConflictService.confirmSaveWithConflictDialog(
                          context: modalCtx,
                          conflicts: currentConflicts,
                          targetName: 'الحصة الاستثنائية لمجموعة "${targetGroup.name}"',
                        );
                    if (!proceed) return;
                  }

                  final session = ExceptionalSessionModel(
                    id: 'EX-${DateTime.now().millisecondsSinceEpoch}',
                    groupId: targetGroup.id,
                    groupName: targetGroup.name,
                    title: reasons.firstWhere((r) => r['key'] == selectedReason)['label'] as String,
                    reason: selectedReason,
                    scale: selectedScale,
                    date: dateStr,
                    day: dayName,
                    time: formatTimeOfDayTo12Hour(selectedTime),
                    isRecurring: isRecurring,
                    notes: notesCtrl.text.trim(),
                    createdAt: DateTime.now().toIso8601String(),
                  );

                  await database.saveExceptionalSession(session);
                  if (!modalCtx.mounted) return;
                  Navigator.pop(modalCtx);
                  onSaved?.call();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم جدولة الحصة الاستثنائية بنجاح لمجموعة "${targetGroup.name}" ⚡'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      );
    },
  );
}
