import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/group_model.dart';
import '../models/curriculum_model.dart';
import '../core/database/database_service.dart';

/// شاشة سفلية (BottomSheet) لاختيار دروس المنهج في دفتر التحضير وكشف الحضور.
/// تتميز بنظام ذكي يحدد:
/// 1. الدروس المشروحة مسبقاً: تظهر مشطوبة بعلامة (تم شرحه ✓) ومغلقة في التحضير الجديد لمنع الخطأ،
///    بينما تكون مفتوحة ومتاحة بالكامل في وضع المراجعة والتسميع.
/// 2. الدرس الذي عليه الدور (Due Lesson): مميز بتأثير بارز (عليه الدور 🎯) وقابل للاختيار.
/// 3. الدروس التالية: قابلة للاختيار بسلاسة.
class AttendanceLessonPickerSheet extends StatefulWidget {
  const AttendanceLessonPickerSheet({
    super.key,
    required this.groupLessons,
    required this.group,
    required this.date,
    required this.initialProgressMap,
    required this.initialTopic,
    required this.database,
    required this.onConfirmed,
    this.isPreviousLessonMode = false,
    this.singleSelect = false,
  });

  final List<CurriculumLessonModel> groupLessons;
  final GroupModel group;
  final String date;
  final Map<int, Map<String, dynamic>> initialProgressMap;
  final String initialTopic;
  final DatabaseService database;
  final ValueChanged<List<CurriculumLessonModel>> onConfirmed;
  final bool isPreviousLessonMode;
  final bool singleSelect;

  @override
  State<AttendanceLessonPickerSheet> createState() =>
      _AttendanceLessonPickerSheetState();
}

class _AttendanceLessonPickerSheetState
    extends State<AttendanceLessonPickerSheet> {
  final Set<int> _selectedLessonIds = {};
  late Map<int, Map<String, dynamic>> _progressMap;
  final Set<String> _pastTaughtTitles = {};
  String _searchQuery = '';
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _progressMap = Map.from(widget.initialProgressMap);
    _initPreselectedLessons();
    _loadPastSessionLogs();
  }

  void _initPreselectedLessons() {
    final currentTopic = widget.initialTopic.trim();
    if (currentTopic.isNotEmpty) {
      for (final l in widget.groupLessons) {
        final lid = l.id;
        final title = l.lessonTitle.isNotEmpty ? l.lessonTitle : l.title;
        if (lid != null && currentTopic.contains(title)) {
          _selectedLessonIds.add(lid);
        }
      }
    }
  }

  Future<void> _loadPastSessionLogs() async {
    try {
      final logs = await widget.database.getSessionLogs(groupId: widget.group.id);
      final titles = <String>{};
      for (final log in logs) {
        if (log.lessonTitle.trim().isNotEmpty) {
          titles.add(log.lessonTitle.trim());
        }
        if (log.previousLessonReview.trim().isNotEmpty) {
          titles.add(log.previousLessonReview.trim());
        }
      }
      if (mounted) {
        setState(() {
          _pastTaughtTitles.addAll(titles);
          _isLoadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  /// فحص ما إذا كان الدرس قد تم شرحه مسبقاً
  bool _isLessonExplained(CurriculumLessonModel lesson) {
    final lid = lesson.id;
    if (lid != null && _progressMap.containsKey(lid)) {
      final status = _progressMap[lid]?['status'] as String? ?? '';
      if (status == 'current' || status == 'previous' || status == 'no_date') {
        return true;
      }
    }
    if (lesson.isCompleted) return true;

    final title = (lesson.lessonTitle.isNotEmpty ? lesson.lessonTitle : lesson.title).trim();
    if (title.isNotEmpty) {
      for (final past in _pastTaughtTitles) {
        if (past.contains(title) || title.contains(past)) {
          return true;
        }
      }
    }
    return false;
  }

  /// حساب فهرس "الدرس الذي عليه الدور" (أول درس لم يتم شرحه بعد بالترتيب)
  int _calculateDueLessonIndex() {
    for (int i = 0; i < widget.groupLessons.length; i++) {
      if (!_isLessonExplained(widget.groupLessons[i])) {
        return i;
      }
    }
    return -1; // جميع الدروس مشروحة
  }

  void _toggleLesson(CurriculumLessonModel lesson, bool isExplained, bool isDue) {
    final lid = lesson.id;
    if (lid == null) return;

    // تمكين اختيار أي درس للمراجعة أو الشرح الجزئي والتكميلي بحرية
    HapticFeedback.selectionClick();
    setState(() {
      if (widget.singleSelect) {
        _selectedLessonIds.clear();
        _selectedLessonIds.add(lid);
      } else {
        if (_selectedLessonIds.contains(lid)) {
          _selectedLessonIds.remove(lid);
        } else {
          _selectedLessonIds.add(lid);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dueIndex = _calculateDueLessonIndex();
    final explainedCount = widget.groupLessons.where(_isLessonExplained).length;
    final totalCount = widget.groupLessons.length;
    final remainingCount = (totalCount - explainedCount).clamp(0, totalCount);

    final filteredLessons = widget.groupLessons.where((l) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      final title = (l.lessonTitle.isNotEmpty ? l.lessonTitle : l.title).toLowerCase();
      final unit = (l.unitName.isNotEmpty ? l.unitName : l.unitTitle).toLowerCase();
      return title.contains(q) || unit.contains(q);
    }).toList();

    // تجميع حسب الوحدة الدراسية
    final units = <String, List<CurriculumLessonModel>>{};
    for (final l in filteredLessons) {
      final uName = l.unitName.isNotEmpty
          ? l.unitName
          : (l.unitTitle.isNotEmpty ? l.unitTitle : 'الوحدة الأولى');
      units.putIfAbsent(uName, () => []).add(l);
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // مقبض السحب العلوي
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),

          // الشريط الرأسي والعنوان
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: widget.isPreviousLessonMode
                        ? Colors.amber.withValues(alpha: 0.15)
                        : const Color(0xFF00F2FE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.isPreviousLessonMode
                        ? Icons.history_edu_rounded
                        : Icons.auto_stories_rounded,
                    color: widget.isPreviousLessonMode
                        ? Colors.amber.shade800
                        : const Color(0xFF0284C7),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isPreviousLessonMode
                            ? 'اختيار موضوع مراجعة الدرس السابق 📖'
                            : 'اختيار موضوع درس الحصة من المنهج 📚',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.isPreviousLessonMode
                            ? 'الدروس التي تم تدريسها مميزة بوضوح ✅ ومتاحة لاختيار أكثر من درس للمراجعة والتسميع'
                            : 'جميع الدروس متاحة للاختيار • إمكانية اختيار درس مشروح للشرح الجزئي والتكميلي 🎯',
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
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // شريط إحصائيات المنهج السريع
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'المنهج: $totalCount درس',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                  const SizedBox(width: 14),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                      const SizedBox(width: 4),
                      Text(
                        'مشروح مسبقاً: $explainedCount',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded, size: 14, color: Colors.blueAccent),
                      const SizedBox(width: 4),
                      Text(
                        'متبقي: $remainingCount',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  if (dueIndex != -1 && !widget.isPreviousLessonMode) ...[
                    const SizedBox(width: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'الدرس المستحق: ${widget.groupLessons[dueIndex].title}',
                        style: const TextStyle(
                          color: Color(0xFF0284C7),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // حقل البحث الذكي
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: 'ابحث عن اسم الدرس أو الوحدة...',
                hintStyle: const TextStyle(fontSize: 12.5),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // قائمة الدروس المصنفة
          Expanded(
            child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : widget.groupLessons.isEmpty
                ? const Center(
                    child: Text('لا توجد دروس مسجلة لهذا المنهج بعد'),
                  )
                : filteredLessons.isEmpty
                ? const Center(
                    child: Text('لا توجد نتائج مطابقة لبحثك'),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    physics: const BouncingScrollPhysics(),
                    children: units.entries.map((entry) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.15),
                          ),
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: true,
                          shape: const RoundedRectangleBorder(side: BorderSide.none),
                          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                          leading: const Icon(
                            Icons.folder_open_rounded,
                            color: Color(0xFF0284C7),
                            size: 22,
                          ),
                          title: Text(
                            entry.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          children: entry.value.map((lesson) {
                            final lid = lesson.id ?? -1;
                            final isSelected = _selectedLessonIds.contains(lid);
                            final isExplained = _isLessonExplained(lesson);
                            final originalIndex = widget.groupLessons.indexOf(lesson);
                            final isDue = (originalIndex == dueIndex);

                            return _buildLessonTile(
                              lesson: lesson,
                              isExplained: isExplained,
                              isDue: isDue,
                              isSelected: isSelected,
                              isDark: isDark,
                            );
                          }).toList(),
                        ),
                      );
                    }).toList(),
                  ),
          ),

          // شريط التأكيد والحفظ السفلي
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.isPreviousLessonMode
                          ? Colors.amber.shade800
                          : const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      widget.isPreviousLessonMode
                          ? Icons.check_circle_outline_rounded
                          : Icons.auto_awesome,
                      size: 20,
                    ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _selectedLessonIds.isEmpty
                            ? 'اختر درساً واحداً على الأقل'
                            : (widget.isPreviousLessonMode
                                ? 'تأكيد اختيار درس المراجعة (${_selectedLessonIds.length}) ✓'
                                : 'تأكيد اختيار درس الحصة (${_selectedLessonIds.length}) 🎯'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    onPressed: _selectedLessonIds.isEmpty
                        ? null
                        : () {
                            final chosen = widget.groupLessons
                                .where((l) => _selectedLessonIds.contains(l.id))
                                .toList();
                            widget.onConfirmed(chosen);
                            Navigator.pop(context);
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// بناء عنصر الدرس المنفرد وفق حالته
  Widget _buildLessonTile({
    required CurriculumLessonModel lesson,
    required bool isExplained,
    required bool isDue,
    required bool isSelected,
    required bool isDark,
  }) {
    final title = lesson.lessonTitle.isNotEmpty ? lesson.lessonTitle : lesson.title;

    // تحديد ألوان وخلفيات العنصر
    Color tileBg = Colors.transparent;
    Border? border;

    if (isSelected) {
      tileBg = widget.isPreviousLessonMode
          ? Colors.amber.withValues(alpha: isDark ? 0.25 : 0.15)
          : const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.15);
      border = Border.all(
        color: widget.isPreviousLessonMode ? Colors.amber.shade600 : const Color(0xFF10B981),
        width: 1.5,
      );
    } else if (isDue && !widget.isPreviousLessonMode) {
      tileBg = const Color(0xFF00F2FE).withValues(alpha: isDark ? 0.12 : 0.08);
      border = Border.all(
        color: const Color(0xFF00F2FE).withValues(alpha: 0.8),
        width: 1.5,
      );
    } else if (isExplained && !widget.isPreviousLessonMode) {
      tileBg = isDark ? Colors.black.withValues(alpha: 0.2) : Colors.grey.shade50;
    }

    // بناء العنوان النصي
    TextStyle titleStyle;
    if (isDue && !widget.isPreviousLessonMode) {
      // الدرس الذي عليه الدور
      titleStyle = TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 14,
        color: isDark ? const Color(0xFF00F2FE) : const Color(0xFF0284C7),
      );
    } else {
      titleStyle = TextStyle(
        fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
        fontSize: 13.5,
        color: isSelected
            ? (widget.isPreviousLessonMode ? Colors.amber.shade900 : const Color(0xFF10B981))
            : (isDark ? Colors.white : const Color(0xFF1E293B)),
      );
    }

    return InkWell(
      onTap: () => _toggleLesson(lesson, isExplained, isDue),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(12),
          border: border ??
              Border(
                bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.08)),
              ),
        ),
        child: Row(
          children: [
            // أيقونة البداية / الشيك بوكس
            if (widget.isPreviousLessonMode) ...[
              Checkbox(
                value: isSelected,
                activeColor: Colors.amber.shade800,
                checkColor: Colors.white,
                onChanged: (_) => _toggleLesson(lesson, isExplained, isDue),
              ),
            ] else if (isExplained) ...[
              // علامة مشروح مسبقاً (متاح للاختيار والشرح الجزئي)
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green.shade400, width: 1.2),
                ),
                child: const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 16),
              ),
            ] else if (isDue) ...[
              // أيقونة عليه الدور
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.4),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.stars_rounded, color: Colors.black87, size: 18),
              ),
            ] else ...[
              // أيقونة الدروس التالية
              CircleAvatar(
                radius: 14,
                backgroundColor: isSelected
                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.15),
                child: Text(
                  '${lesson.chapterNumber > 0 ? lesson.chapterNumber : "•"}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? const Color(0xFF10B981) : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),

            // عنوان وتفاصيل الدرس
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: titleStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (lesson.objectives.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      lesson.objectives,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // البادج الذكي على اليمين
            _buildSmartStatusBadge(isExplained: isExplained, isDue: isDue, isSelected: isSelected),
          ],
        ),
      ),
    );
  }

  /// شارة الحالة الذكية
  Widget _buildSmartStatusBadge({
    required bool isExplained,
    required bool isDue,
    required bool isSelected,
  }) {
    if (widget.isPreviousLessonMode) {
      if (isExplained) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5), width: 1.2),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF10B981)),
              SizedBox(width: 4),
              Text(
                'تم تدريسه سابقاً ✅',
                style: TextStyle(
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'لم يُدرَس بعد ⏳',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 10,
          ),
        ),
      );
    }

    if (isExplained) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.teal.shade400.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_edu_rounded, size: 12, color: Colors.teal),
            SizedBox(width: 4),
            Text(
              'مشروح سابقاً ✓ (متاح جزئي)',
              style: TextStyle(
                color: Colors.teal,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    if (isDue) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stars_rounded, size: 12, color: Colors.black87),
            SizedBox(width: 4),
            Text(
              'عليه الدور 🎯',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: const Text(
        'درس قادم ⏳',
        style: TextStyle(
          color: Colors.blueAccent,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
