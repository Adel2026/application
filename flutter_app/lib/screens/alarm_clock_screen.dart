import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/alarm_service.dart';
import '../core/database/database_service.dart';
import '../core/notification_service.dart';
import '../models/app_alarm_model.dart';
import '../models/group_model.dart';
import '../models/school_period_model.dart';

class AlarmClockScreen extends StatefulWidget {
  final DatabaseService database;

  const AlarmClockScreen({
    super.key,
    required this.database,
  });

  @override
  State<AlarmClockScreen> createState() => _AlarmClockScreenState();
}

class _AlarmClockScreenState extends State<AlarmClockScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _liveClockTimer;
  DateTime _currentTime = DateTime.now();

  bool _isLoading = true;
  List<AppAlarmModel> _allAlarms = [];
  Set<String> _disabledAlarmIds = {};
  List<AppAlarmModel> _customAlarms = [];

  List<SchoolPeriodModel> _schoolPeriods = [];
  List<GroupModel> _groups = [];

  // --- Day Filter & Integrated Day Bar (Same style as Groups Timetable) ---
  late String _selectedFilterDay;
  bool _isDaysBarExpanded = false;

  static const List<String> _filterDaysList = [
    'الكل',
    'السبت',
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
  ];

  // --- In-App Alarm Settings (100% Controlled Inside The App) ---
  String _selectedTone = 'school_bell';
  String? _customAudioPath;
  String? _customAudioTitle;
  List<Map<String, String>> _deviceRingtones = [];
  bool _isLoadingRingtones = false;
  String? _currentlyPlayingAudio; // tracking current audio preview source

  double _alarmVolume = 0.85;
  bool _vibrationEnabled = true;
  int _defaultMinutesBefore = 5;
  int _snoozeMinutes = 5;
  int _autoSilenceSeconds = 60;
  bool _autoDeleteExpired = true;
  bool _autoSyncTomorrow = true;
  bool _alarmsMasterActive = true;

  static const List<String> _weekdaysArabic = [
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  ];

  static const List<String> _weekdaysShort = [
    'ح',
    'ن',
    'ث',
    'ر',
    'خ',
    'ج',
    'س',
  ];

  @override
  void initState() {
    super.initState();
    _selectedFilterDay = _getTodayName(DateTime.now().weekday);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    // Start live clock ticking every second
    _liveClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });

    _loadAlarmsData();
  }

  @override
  void dispose() {
    _stopAudioPreview();
    _liveClockTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAlarmsData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Load in-app settings
      _selectedTone = await widget.database.getSetting('alarm_sound_tone', defaultValue: 'school_bell');
      _customAudioPath = await widget.database.getSetting('alarm_custom_audio_path', defaultValue: '');
      if (_customAudioPath!.isEmpty) _customAudioPath = null;
      _customAudioTitle = await widget.database.getSetting('alarm_custom_audio_title', defaultValue: '');
      if (_customAudioTitle!.isEmpty) _customAudioTitle = null;

      final volStr = await widget.database.getSetting('alarm_volume', defaultValue: '0.85');
      _alarmVolume = double.tryParse(volStr) ?? 0.85;
      final vibStr = await widget.database.getSetting('alarm_vibration_enabled', defaultValue: 'true');
      _vibrationEnabled = vibStr == 'true';
      final minStr = await widget.database.getSetting('school_auto_alarm_minutes_before', defaultValue: '5');
      _defaultMinutesBefore = int.tryParse(minStr) ?? 5;
      final snoozeStr = await widget.database.getSetting('alarm_snooze_minutes', defaultValue: '5');
      _snoozeMinutes = int.tryParse(snoozeStr) ?? 5;
      final silenceStr = await widget.database.getSetting('alarm_auto_silence_seconds', defaultValue: '60');
      _autoSilenceSeconds = int.tryParse(silenceStr) ?? 60;
      final delStr = await widget.database.getSetting('school_auto_delete_expired_alarms', defaultValue: 'true');
      _autoDeleteExpired = delStr == 'true';
      final syncStr = await widget.database.getSetting('school_auto_next_day_alarm', defaultValue: 'true');
      _autoSyncTomorrow = syncStr == 'true';
      final masterStr = await widget.database.getSetting('alarm_master_active', defaultValue: 'true');
      _alarmsMasterActive = masterStr == 'true';

      // 2. Load disabled IDs set
      final disabledStr = await widget.database.getSetting('app_alarms_disabled_keys_v1', defaultValue: '[]');
      try {
        final List list = jsonDecode(disabledStr);
        _disabledAlarmIds = list.map((e) => e.toString()).toSet();
      } catch (_) {
        _disabledAlarmIds = {};
      }

      // 3. Load custom alarms
      final customStr = await widget.database.getSetting('app_custom_alarms_v1', defaultValue: '[]');
      try {
        final List list = jsonDecode(customStr);
        _customAlarms = list.map((e) => AppAlarmModel.fromMap(Map<String, dynamic>.from(e))).toList();
      } catch (_) {
        _customAlarms = [];
      }

      // 4. Load School Periods
      _schoolPeriods = await widget.database.getSchoolPeriods();

      // 5. Load Groups
      _groups = await widget.database.getGroups();

      _buildUnifiedAlarmsList();
    } catch (e) {
      debugPrint('Error loading alarms data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _buildUnifiedAlarmsList() {
    final List<AppAlarmModel> list = [];

    // 1. School Periods -> Alarms
    for (final period in _schoolPeriods) {
      if (period.isReserve) continue;
      final parts = period.startTime.split(':');
      if (parts.length < 2) continue;
      final h = int.tryParse(parts[0].trim()) ?? 0;
      final m = int.tryParse(parts[1].trim()) ?? 0;

      final id = 'period_${period.id}';
      final isEnabled = _alarmsMasterActive && !_disabledAlarmIds.contains(id);

      list.add(AppAlarmModel(
        id: id,
        title: 'حصة ${period.periodNumber} (${period.className})',
        subtitle: period.subject.isNotEmpty ? period.subject : 'جدول المدرسة',
        hour: h,
        minute: m,
        days: [period.dayOfWeek],
        isEnabled: isEnabled,
        type: AppAlarmType.school,
        minutesBefore: _defaultMinutesBefore,
        isVibrate: _vibrationEnabled,
        sourceId: period.id.toString(),
      ));
    }

    // 2. Groups -> Alarms
    for (final group in _groups) {
      if (group.startTime.trim().isEmpty) continue;
      final parts = group.startTime.trim().split(RegExp(r'[:\s]+'));
      if (parts.length < 2) continue;
      int? h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) continue;
      if (group.startTime.contains('م') || group.startTime.toLowerCase().contains('pm')) {
        if (h < 12) h += 12;
      } else if (group.startTime.contains('ص') || group.startTime.toLowerCase().contains('am')) {
        if (h == 12) h = 0;
      }

      final id = 'group_${group.id}';
      final isEnabled = _alarmsMasterActive && !_disabledAlarmIds.contains(id);

      final days = _weekdaysArabic.where((d) => group.schedule.contains(d) || group.days.contains(d)).toList();

      list.add(AppAlarmModel(
        id: id,
        title: group.name,
        subtitle: group.subject.isNotEmpty ? '${group.subject} • ${group.grade}' : group.grade,
        hour: h,
        minute: m,
        days: days.isNotEmpty ? days : ['الأحد'],
        isEnabled: isEnabled,
        type: AppAlarmType.group,
        minutesBefore: _defaultMinutesBefore,
        isVibrate: _vibrationEnabled,
        sourceId: group.id.toString(),
      ));
    }

    // 3. Custom Alarms
    for (final custom in _customAlarms) {
      final isEnabled = _alarmsMasterActive && !_disabledAlarmIds.contains(custom.id);
      list.add(custom.copyWith(isEnabled: isEnabled));
    }

    // Sort by time: hour then minute
    list.sort((a, b) {
      if (a.hour != b.hour) return a.hour.compareTo(b.hour);
      return a.minute.compareTo(b.minute);
    });

    _allAlarms = list;
  }

  Future<void> _saveDisabledIds() async {
    await widget.database.setSetting(
      'app_alarms_disabled_keys_v1',
      jsonEncode(_disabledAlarmIds.toList()),
    );
  }

  Future<void> _saveCustomAlarms() async {
    await widget.database.setSetting(
      'app_custom_alarms_v1',
      jsonEncode(_customAlarms.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> _toggleAlarm(AppAlarmModel alarm, bool val) async {
    HapticFeedback.mediumImpact();
    setState(() {
      if (val) {
        _disabledAlarmIds.remove(alarm.id);
      } else {
        _disabledAlarmIds.add(alarm.id);
      }
      _buildUnifiedAlarmsList();
    });

    await _saveDisabledIds();

    if (val) {
      for (final day in alarm.days) {
        await NotificationService.scheduleTimetableAlarm(
          key: alarm.id,
          dayName: day,
          title: alarm.title,
          body: alarm.subtitle,
          hour: alarm.hour,
          minute: alarm.minute,
          minutesBefore: alarm.minutesBefore,
          isAutomatic: false,
          soundTone: _selectedTone,
        );
      }
      if (mounted) {
        final updatedAlarm = _allAlarms.firstWhere((a) => a.id == alarm.id, orElse: () => alarm);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تفعيل المنبه ⏰ (${updatedAlarm.nextOccurrenceArabicText})'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      await NotificationService.cancelAlarmByKey(alarm.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إيقاف منبه "${alarm.title}" مؤقتاً ⏸️'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Custom Minutes Before Picker Dialog/Sheet (Any user-defined duration in minutes)
  Future<void> _showMinutesBeforePicker(AppAlarmModel alarm) async {
    HapticFeedback.selectionClick();
    int tempMinutes = alarm.minutesBefore;
    final textController = TextEditingController(
      text: (tempMinutes != 0 && tempMinutes != 5 && tempMinutes != 10 && tempMinutes != 15)
          ? tempMinutes.toString()
          : '',
    );

    const presets = [0, 5, 10, 15, 20, 30, 45, 60];

    final selectedMinutes = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (ctx, setPickerState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 18,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: Color(0xFFFBBF24), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تحديد وقت التنبيه المسبق ⏱️',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Text(
                  'لمنبه: "${alarm.title}" (${alarm.digitalTime} ${alarm.periodArabic})',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const Text(
                  'خيارات سريعة جاهزة:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presets.map((min) {
                    final isSel = tempMinutes == min;
                    final label = min == 0
                        ? 'في الموعد'
                        : (min == 60 ? 'ساعة (60 د)' : '$min دقيقة');
                    return ChoiceChip(
                      selected: isSel,
                      label: Text(label),
                      selectedColor: const Color(0xFFFBBF24),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      onSelected: (val) {
                        setPickerState(() {
                          tempMinutes = min;
                          textController.clear();
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                const Text(
                  'أو حدد عدد الدقائق بدقة يدوياً:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: textController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          hintText: 'مثال: 25 أو 40 دقيقة',
                          suffixText: 'دقيقة',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed >= 0) {
                            setPickerState(() => tempMinutes = parsed);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    tempMinutes == 0
                        ? 'ضبط التنبيه: في نفس الموعد تماماً'
                        : 'ضبط التنبيه: قبل الموعد بـ $tempMinutes دقيقة ⏱️',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () => Navigator.pop(ctx, tempMinutes),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (selectedMinutes != null && selectedMinutes != alarm.minutesBefore) {
      if (alarm.type == AppAlarmType.custom) {
        final index = _customAlarms.indexWhere((a) => a.id == alarm.id);
        if (index != -1) {
          _customAlarms[index] = _customAlarms[index].copyWith(minutesBefore: selectedMinutes);
          await _saveCustomAlarms();
        }
      }

      if (alarm.isEnabled) {
        await NotificationService.cancelAlarmByKey(alarm.id);
        for (final day in alarm.days) {
          await NotificationService.scheduleTimetableAlarm(
            key: alarm.id,
            dayName: day,
            title: alarm.title,
            body: alarm.subtitle,
            hour: alarm.hour,
            minute: alarm.minute,
            minutesBefore: selectedMinutes,
            soundTone: _selectedTone,
          );
        }
      }

      setState(() {
        _buildUnifiedAlarmsList();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selectedMinutes == 0
                  ? 'تم ضبط التنبيه: في الموعد تماماً ⏰'
                  : 'تم ضبط التنبيه: قبل الموعد بـ $selectedMinutes دقيقة ⏱️',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _deleteAlarm(AppAlarmModel alarm) async {
    HapticFeedback.heavyImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنبه 🗑️', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('هل تريد حذف منبه "${alarm.title}" نهائياً من قائمة المنبهات؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await NotificationService.cancelAlarmByKey(alarm.id);
      if (alarm.type == AppAlarmType.custom) {
        _customAlarms.removeWhere((e) => e.id == alarm.id);
        await _saveCustomAlarms();
      } else {
        _disabledAlarmIds.add(alarm.id);
        await _saveDisabledIds();
      }

      setState(() {
        _buildUnifiedAlarmsList();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف المنبه بنجاح 🗑️'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  /// Synchronize all timetable periods and groups in-app
  Future<void> _syncTimetableAlarms() async {
    HapticFeedback.heavyImpact();
    setState(() => _isLoading = true);

    try {
      int totalCount = await AlarmService.syncDayPeriodAlarms(
        dayPeriods: _schoolPeriods.where((p) => !p.isReserve).toList(),
        minutesBefore: _defaultMinutesBefore,
        isAutomatic: false,
        soundTone: _selectedTone,
      );

      for (final day in _weekdaysArabic) {
        final dayGroups = _groups.where((g) => g.schedule.contains(day) || g.days.contains(day)).toList();
        if (dayGroups.isNotEmpty) {
          totalCount += await AlarmService.syncDayGroupAlarms(
            dayGroups: dayGroups,
            dayName: day,
            minutesBefore: _defaultMinutesBefore,
            isAutomatic: false,
            soundTone: _selectedTone,
          );
        }
      }

      _disabledAlarmIds.clear();
      await _saveDisabledIds();
      await _loadAlarmsData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت مزامنة وتفعيل $totalCount حصة ومجموعة كمنبهات ذكية بنجاح! 🔄'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Sync alarms error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- Audio Preview / Test Management ---
  Future<void> _playAudioPreview({String? uri, String? filePath, String? toneId, String sourceKey = 'general'}) async {
    HapticFeedback.selectionClick();
    if (_currentlyPlayingAudio != null) {
      await AlarmService.stopAudio();
      if (_currentlyPlayingAudio == sourceKey) {
        setState(() => _currentlyPlayingAudio = null);
        return;
      }
    }

    setState(() => _currentlyPlayingAudio = sourceKey);

    if (toneId != null && toneId.isNotEmpty) {
      await AlarmService.playAudio(toneId: toneId, durationMs: 7000);
    } else if (filePath != null && filePath.isNotEmpty) {
      await AlarmService.playAudio(filePath: filePath, durationMs: 7000);
    } else if (uri != null && uri.isNotEmpty) {
      await AlarmService.playAudio(uri: uri, durationMs: 7000);
    } else {
      await AlarmService.playAudio(toneId: _selectedTone, durationMs: 7000);
    }

    Future.delayed(const Duration(milliseconds: 7200), () {
      if (mounted && _currentlyPlayingAudio == sourceKey) {
        setState(() => _currentlyPlayingAudio = null);
      }
    });
  }

  Future<void> _stopAudioPreview() async {
    await AlarmService.stopAudio();
    if (mounted) setState(() => _currentlyPlayingAudio = null);
  }

  Future<void> _loadDeviceRingtones() async {
    if (_deviceRingtones.isNotEmpty) return;
    setState(() => _isLoadingRingtones = true);
    try {
      final list = await AlarmService.getDeviceRingtones();
      if (mounted) {
        setState(() {
          _deviceRingtones = list;
          _isLoadingRingtones = false;
        });
      }
    } catch (e) {
      debugPrint('Error getting ringtones: $e');
      if (mounted) setState(() => _isLoadingRingtones = false);
    }
  }

  /// Open comprehensive audio & device ringtones selector sheet
  Future<void> _openSoundSelectorSheet() async {
    HapticFeedback.selectionClick();
    await _loadDeviceRingtones();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (ctx, setSoundState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            padding: const EdgeInsets.only(top: 18, left: 18, right: 18, bottom: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.music_note_rounded, color: Color(0xFF00F2FE), size: 24),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'صوتيات ونغمات المنبه 🎶',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _stopAudioPreview();
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 1. Highlighted Card: Pick from Internal Storage
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                          : [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _customAudioPath != null
                          ? const Color(0xFF10B981)
                          : (isDark ? const Color(0xFF334155) : const Color(0xFF86EFAC)),
                      width: _customAudioPath != null ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.folder_special_rounded, color: Color(0xFF10B981), size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'تخصيص ملف صوتي من الذاكرة الداخلية 📁',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.audio_file_rounded, size: 16),
                            label: const Text('اختيار ملف 📂', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              HapticFeedback.selectionClick();
                              try {
                                final res = await FilePicker.pickFiles(
                                  type: FileType.audio,
                                );
                                if (res.isNotEmpty && res.first.path != null) {
                                  final p = res.first.path!;
                                  final n = res.first.name;
                                  setState(() {
                                    _customAudioPath = p;
                                    _customAudioTitle = n;
                                  });
                                  setSoundState(() {});
                                  await widget.database.setSetting('alarm_custom_audio_path', p);
                                  await widget.database.setSetting('alarm_custom_audio_title', n);
                                  await _playAudioPreview(filePath: p, sourceKey: 'custom_file');
                                  setSoundState(() {});
                                }
                              } catch (e) {
                                debugPrint('Error picking audio: $e');
                              }
                            },
                          ),
                        ],
                      ),
                      if (_customAudioPath != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _customAudioTitle ?? _customAudioPath!.split('/').last,
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Preview button
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                                icon: Icon(
                                  _currentlyPlayingAudio == 'custom_file' ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                                  color: const Color(0xFF10B981),
                                  size: 22,
                                ),
                                onPressed: () async {
                                  await _playAudioPreview(filePath: _customAudioPath, sourceKey: 'custom_file');
                                  setSoundState(() {});
                                },
                              ),
                              const SizedBox(width: 4),
                              // Clear button
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                                icon: const Icon(Icons.clear_rounded, color: Color(0xFFEF4444), size: 18),
                                onPressed: () async {
                                  _stopAudioPreview();
                                  setState(() {
                                    _customAudioPath = null;
                                    _customAudioTitle = null;
                                  });
                                  setSoundState(() {});
                                  await widget.database.setSetting('alarm_custom_audio_path', '');
                                  await widget.database.setSetting('alarm_custom_audio_title', '');
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Built-in App Sounds
                const Text('نغمات التطبيق المدمجة 🔔:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    {'id': 'school_bell', 'name': 'جرس الحصة 🔔'},
                    {'id': 'alarm_climb', 'name': 'رنين متصاعد ⏰'},
                    {'id': 'digital_beep', 'name': 'نغمة رقمية 🎶'},
                    {'id': 'gentle_melody', 'name': 'نغمة هادئة 🎵'},
                    {'id': 'system_default', 'name': 'تنبيه النظام 📱'},
                  ].map((item) {
                    final isSel = _selectedTone == item['id'] && _customAudioPath == null;
                    return ChoiceChip(
                      selected: isSel,
                      label: Text(item['name']!),
                      selectedColor: const Color(0xFF00F2FE),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      onSelected: (val) async {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedTone = item['id']!;
                          _customAudioPath = null;
                          _customAudioTitle = null;
                        });
                        setSoundState(() {});
                        await widget.database.setSetting('alarm_sound_tone', item['id']!);
                        await widget.database.setSetting('alarm_custom_audio_path', '');
                        await widget.database.setSetting('alarm_custom_audio_title', '');
                        await _playAudioPreview(toneId: item['id']!, sourceKey: 'builtin_${item['id']}');
                        setSoundState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // 3. Synced Device Ringtones List
                Row(
                  children: [
                    const Icon(Icons.phonelink_ring_rounded, color: Color(0xFFFBBF24), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'صوتيات الموبايل المتزامنة (${_deviceRingtones.length}) 📱',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (_isLoadingRingtones)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFBBF24)),
                      )
                    else
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.sync_rounded, size: 14, color: Color(0xFFFBBF24)),
                        label: const Text('إعادة مزامنة', style: TextStyle(fontSize: 11, color: Color(0xFFFBBF24))),
                        onPressed: () async {
                          _deviceRingtones.clear();
                          await _loadDeviceRingtones();
                          setSoundState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                // Ringtones List
                Expanded(
                  child: _deviceRingtones.isEmpty
                      ? Center(
                          child: _isLoadingRingtones
                              ? const CircularProgressIndicator(color: Color(0xFF00F2FE))
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.phonelink_erase_rounded, size: 36, color: Colors.grey),
                                    const SizedBox(height: 8),
                                    const Text('اضغط لمزامنة كافة نغمات وتنبيهات الهاتف', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        await _loadDeviceRingtones();
                                        setSoundState(() {});
                                      },
                                      icon: const Icon(Icons.sync_rounded, size: 16),
                                      label: const Text('مزامنة الصوتيات الآن 🔄'),
                                    ),
                                  ],
                                ),
                        )
                      : ListView.builder(
                          itemCount: _deviceRingtones.length,
                          itemBuilder: (lCtx, index) {
                            final item = _deviceRingtones[index];
                            final title = item['title'] ?? 'نغمة ${index + 1}';
                            final uri = item['uri'] ?? '';
                            final isSel = _selectedTone == uri;
                            final isPlaying = _currentlyPlayingAudio == 'ringtone_$index';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? const Color(0xFF00F2FE).withValues(alpha: 0.12)
                                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSel
                                      ? const Color(0xFF00F2FE)
                                      : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                leading: Icon(
                                  isSel ? Icons.check_circle_rounded : Icons.music_note_rounded,
                                  color: isSel ? const Color(0xFF00F2FE) : Colors.grey,
                                  size: 20,
                                ),
                                title: Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                    color: isSel ? (isDark ? Colors.white : Colors.black) : null,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4),
                                      icon: Icon(
                                        isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_outline_rounded,
                                        color: isPlaying ? const Color(0xFFEF4444) : const Color(0xFFFBBF24),
                                        size: 22,
                                      ),
                                      onPressed: () async {
                                        await _playAudioPreview(uri: uri, sourceKey: 'ringtone_$index');
                                        setSoundState(() {});
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    FilledButton.tonal(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () async {
                                        HapticFeedback.mediumImpact();
                                        setState(() {
                                          _selectedTone = uri;
                                          _customAudioPath = null;
                                          _customAudioTitle = title;
                                        });
                                        setSoundState(() {});
                                        await widget.database.setSetting('alarm_sound_tone', uri);
                                        await widget.database.setSetting('alarm_custom_audio_path', '');
                                        await widget.database.setSetting('alarm_custom_audio_title', title);
                                        _stopAudioPreview();
                                        Navigator.pop(ctx);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('تم تعيين نغمة المنبه: $title 🔔'),
                                              backgroundColor: const Color(0xFF10B981),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      },
                                      child: const Text('تعيين', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
          );
        },
      ),
    );
  }

  /// Open comprehensive in-app alarm settings bottom sheet
  Future<void> _openAlarmSettingsSheet() async {
    HapticFeedback.selectionClick();

    String tempTone = _selectedTone;
    double tempVolume = _alarmVolume;
    bool tempVibration = _vibrationEnabled;
    int tempMinutesBefore = _defaultMinutesBefore;
    int tempSnooze = _snoozeMinutes;
    int tempSilence = _autoSilenceSeconds;
    bool tempAutoDelete = _autoDeleteExpired;
    bool tempAutoSync = _autoSyncTomorrow;
    bool tempMaster = _alarmsMasterActive;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: Color(0xFF00F2FE), size: 24),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'إعدادات المنبه الذكي الشاملة ⚙️',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'تحكم كامل في نغمات الموبايل، التنبيه المسبق بالدقائق، والتحكم التام في المنبهات.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 14),

                // Content List
                Expanded(
                  child: ListView(
                    children: [
                      // 1. Master Alarms Switch
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tempMaster
                              ? const Color(0xFF10B981).withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: tempMaster
                                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                : Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'تشغيل كافة المنبهات العامة ⏰',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            tempMaster
                                ? 'المنبهات نشطة وجاهزة للرنين بمواعيدها.'
                                : 'وضع الإجازة: تم تعطيل رنين المنبهات مؤقتاً.',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          value: tempMaster,
                          activeTrackColor: const Color(0xFF10B981),
                          onChanged: (val) {
                            setModalState(() => tempMaster = val);
                          },
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 2. Sound, Ringtones & Internal Storage Selector
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.music_note_rounded, color: Color(0xFF00F2FE), size: 20),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'نغمة وصوت المنبه 🔔',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(Icons.audio_file_rounded, size: 14),
                                  label: const Text('تخصيص / مزامنة 📱', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _openSoundSelectorSheet();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            if (_customAudioPath != null) ...[
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('ملف صوتي مخصص من الذاكرة الداخلية:', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                          Text(
                                            _customAudioTitle ?? _customAudioPath!.split('/').last,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF10B981)),
                                      onPressed: () => _playAudioPreview(filePath: _customAudioPath, sourceKey: 'settings_custom'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],

                            DropdownButtonFormField<String>(
                              initialValue: tempTone.contains('/') ? 'system_default' : tempTone,
                              isExpanded: true,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'school_bell', child: Text('جرس الحصة المدرسي الكلاسيكي 🔔', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'alarm_climb', child: Text('رنين منبه متصاعد قوي ⏰', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'digital_beep', child: Text('نغمة إلكترونية سريعة 🎶', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'gentle_melody', child: Text('نغمة هادئة لطيفة 🎵', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'system_default', child: Text('صوت التنبيه الافتراضي للنظام 📱', overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (val) {
                                if (val != null) setModalState(() => tempTone = val);
                              },
                            ),
                            const SizedBox(height: 10),

                            // Test Tone Button
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFFBBF24)),
                                  foregroundColor: const Color(0xFFFBBF24),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                label: const Text('تجربة النغمة الآن 🎵', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                onPressed: () async {
                                  await _playAudioPreview(
                                    toneId: _customAudioPath == null ? tempTone : null,
                                    filePath: _customAudioPath,
                                    sourceKey: 'settings_preview',
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 3. Volume & Vibration
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.volume_up_rounded, color: Color(0xFFFBBF24), size: 18),
                                const SizedBox(width: 8),
                                const Text('مستوى صوت المنبه:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Text(
                                  '${(tempVolume * 100).toInt()}%',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFBBF24)),
                                ),
                              ],
                            ),
                            Slider(
                              value: tempVolume,
                              min: 0.1,
                              max: 1.0,
                              divisions: 9,
                              activeColor: const Color(0xFFFBBF24),
                              onChanged: (val) => setModalState(() => tempVolume = val),
                            ),
                            const Divider(height: 16),

                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Row(
                                children: [
                                  Icon(Icons.vibration_rounded, color: Color(0xFFA855F7), size: 18),
                                  SizedBox(width: 8),
                                  Text('تفعيل الاهتزاز مع المنبه', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              value: tempVibration,
                              activeTrackColor: const Color(0xFFA855F7),
                              onChanged: (val) => setModalState(() => tempVibration = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 4. Advance Notice & Timing
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.timer_outlined, color: Color(0xFF00F2FE), size: 18),
                                SizedBox(width: 8),
                                Text('التوقيتات والإنذار المسبق بالدقائق ⏱️', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Default Minutes Before with custom number support
                            Row(
                              children: [
                                const Text('التنبيه المسبق الافتراضي:', style: TextStyle(fontSize: 12)),
                                const Spacer(),
                                InkWell(
                                  onTap: () async {
                                    final customController = TextEditingController(text: tempMinutesBefore.toString());
                                    final picked = await showDialog<int>(
                                      context: ctx,
                                      builder: (dCtx) => AlertDialog(
                                        title: const Text('حدد مدة التنبيه المسبق بالدقائق ⏱️', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                        content: TextField(
                                          controller: customController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          decoration: const InputDecoration(
                                            labelText: 'عدد الدقائق قبل الموعد',
                                            hintText: 'مثال: 0 (في الموعد)، 5، 15، 30',
                                            suffixText: 'دقيقة',
                                          ),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء')),
                                          FilledButton(
                                            onPressed: () {
                                              final val = int.tryParse(customController.text.trim()) ?? 0;
                                              Navigator.pop(dCtx, val);
                                            },
                                            child: const Text('تأكيد'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (picked != null) {
                                      setModalState(() => tempMinutesBefore = picked);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          tempMinutesBefore == 0 ? 'في الموعد تماماً' : 'قبل بـ $tempMinutesBefore دقيقة',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24)),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.edit_rounded, size: 14, color: Color(0xFFFBBF24)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 14),

                            // Snooze Duration
                            Row(
                              children: [
                                const Text('مدة الغفوة (Snooze):', style: TextStyle(fontSize: 12)),
                                const Spacer(),
                                DropdownButton<int>(
                                  value: tempSnooze,
                                  underline: const SizedBox.shrink(),
                                  items: const [
                                    DropdownMenuItem(value: 5, child: Text('5 دقائق')),
                                    DropdownMenuItem(value: 10, child: Text('10 دقائق')),
                                    DropdownMenuItem(value: 15, child: Text('15 دقيقة')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setModalState(() => tempSnooze = val);
                                  },
                                ),
                              ],
                            ),
                            const Divider(height: 14),

                            // Auto Silence Duration
                            Row(
                              children: [
                                const Text('إيقاف الرنين تلقائياً بعد:', style: TextStyle(fontSize: 12)),
                                const Spacer(),
                                DropdownButton<int>(
                                  value: tempSilence,
                                  underline: const SizedBox.shrink(),
                                  items: const [
                                    DropdownMenuItem(value: 30, child: Text('30 ثانية')),
                                    DropdownMenuItem(value: 60, child: Text('1 دقيقة')),
                                    DropdownMenuItem(value: 120, child: Text('دقيقتان')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setModalState(() => tempSilence = val);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 5. Automation & Auto Delete Expired
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.auto_delete_rounded, color: Color(0xFF10B981), size: 18),
                                SizedBox(width: 8),
                                Text('الأتمتة والحذف التلقائي ♻️', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Auto-Delete
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('الحذف التلقائي للمنبهات المنتهية', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              subtitle: const Text('يمسح التنبيه فور انتهاء وقت الحصة ليبقى جدولك نظيفاً.', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                              value: tempAutoDelete,
                              activeTrackColor: const Color(0xFF10B981),
                              onChanged: (val) => setModalState(() => tempAutoDelete = val),
                            ),
                            const Divider(height: 12),

                            // Auto-Sync Next Day
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('المزامنة التلقائية لجدول الغد', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              subtitle: const Text('يجدول منبهات اليوم التالي تلقائياً عند منتصف الليل.', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                              value: tempAutoSync,
                              activeTrackColor: const Color(0xFF00F2FE),
                              onChanged: (val) => setModalState(() => tempAutoSync = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),

                // Save Button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: const Text(
                    'حفظ وتطبيق الإعدادات 💾',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: () async {
                    HapticFeedback.mediumImpact();

                    _selectedTone = tempTone;
                    _alarmVolume = tempVolume;
                    _vibrationEnabled = tempVibration;
                    _defaultMinutesBefore = tempMinutesBefore;
                    _snoozeMinutes = tempSnooze;
                    _autoSilenceSeconds = tempSilence;
                    _autoDeleteExpired = tempAutoDelete;
                    _autoSyncTomorrow = tempAutoSync;
                    _alarmsMasterActive = tempMaster;

                    await widget.database.setSetting('alarm_sound_tone', _selectedTone);
                    await widget.database.setSetting('alarm_volume', _alarmVolume.toString());
                    await widget.database.setSetting('alarm_vibration_enabled', _vibrationEnabled ? 'true' : 'false');
                    await widget.database.setSetting('school_auto_alarm_minutes_before', _defaultMinutesBefore.toString());
                    await widget.database.setSetting('alarm_snooze_minutes', _snoozeMinutes.toString());
                    await widget.database.setSetting('alarm_auto_silence_seconds', _autoSilenceSeconds.toString());
                    await widget.database.setSetting('school_auto_delete_expired_alarms', _autoDeleteExpired ? 'true' : 'false');
                    await widget.database.setSetting('school_auto_next_day_alarm', _autoSyncTomorrow ? 'true' : 'false');
                    await widget.database.setSetting('alarm_master_active', _alarmsMasterActive ? 'true' : 'false');

                    _stopAudioPreview();
                    Navigator.pop(ctx);
                    _loadAlarmsData();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم حفظ وتطبيق كافة إعدادات المنبه بنجاح! 💾✨'),
                          backgroundColor: Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAddOrEditAlarmSheet([AppAlarmModel? editAlarm]) async {
    HapticFeedback.selectionClick();
    TimeOfDay selectedTime = editAlarm != null
        ? TimeOfDay(hour: editAlarm.hour, minute: editAlarm.minute)
        : TimeOfDay.now();
    final titleController = TextEditingController(text: editAlarm?.title ?? '');
    final subtitleController = TextEditingController(text: editAlarm?.subtitle ?? '');
    List<String> selectedDays = editAlarm != null
        ? List.from(editAlarm.days)
        : ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
    int minutesBefore = editAlarm?.minutesBefore ?? _defaultMinutesBefore;
    final customMinController = TextEditingController(
      text: (minutesBefore != 0 && minutesBefore != 5 && minutesBefore != 10 && minutesBefore != 15)
          ? minutesBefore.toString()
          : '',
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          final h = selectedTime.hour % 12 == 0 ? 12 : selectedTime.hour % 12;
          final timeStr = '${h.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')} ${selectedTime.hour < 12 ? 'ص' : 'م'}';

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Row(
                    children: [
                      const Icon(Icons.alarm_add_rounded, color: Color(0xFF00F2FE), size: 26),
                      const SizedBox(width: 10),
                      Text(
                        editAlarm == null ? 'إضافة منبه جديد ⏰' : 'تعديل المنبه ⏰',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Digital Time Picker Card
                  InkWell(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: selectedTime,
                        helpText: 'اختر وقت رنين المنبه',
                        cancelText: 'إلغاء',
                        confirmText: 'تأكيد الوقت',
                      );
                      if (picked != null) {
                        setSheetState(() => selectedTime = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                              : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'وقت رنين المنبه (اضغط للتغيير)',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF00F2FE),
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Title Input
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'اسم المنبه / الحصة / المجموعة',
                      hintText: 'مثال: موعد مراجعة، حصة إضافية، تنبيه واجب',
                      prefixIcon: const Icon(Icons.label_important_outline_rounded, color: Color(0xFF00F2FE)),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Subtitle Input
                  TextField(
                    controller: subtitleController,
                    decoration: InputDecoration(
                      labelText: 'ملاحظة أو وصف إضافي (اختياري)',
                      hintText: 'مثال: لا تنسى تحضير ورق العمل',
                      prefixIcon: const Icon(Icons.notes_rounded, color: Colors.grey),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Days Selection Row
                  const Text('أيام تكرار المنبه:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _weekdaysArabic.map((day) {
                      final isSelected = selectedDays.contains(day);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(day, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        selectedColor: const Color(0xFF00F2FE).withValues(alpha: 0.25),
                        checkmarkColor: const Color(0xFF00F2FE),
                        onSelected: (val) {
                          setSheetState(() {
                            if (val) {
                              selectedDays.add(day);
                            } else {
                              selectedDays.remove(day);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Custom Minutes Before Selector (Presets + Text field)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 18, color: Color(0xFFFBBF24)),
                          const SizedBox(width: 8),
                          const Text('التنبيه المسبق بالدقائق:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(
                            minutesBefore == 0 ? 'في الموعد' : 'قبل بـ $minutesBefore دقيقة',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [0, 5, 10, 15, 20, 30, 45, 60].map((min) {
                          final isSel = minutesBefore == min;
                          final label = min == 0 ? 'في الموعد' : (min == 60 ? 'ساعة (60 د)' : '$min د');
                          return ChoiceChip(
                            selected: isSel,
                            label: Text(label),
                            selectedColor: const Color(0xFFFBBF24),
                            labelStyle: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              color: isSel ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            onSelected: (val) {
                              setSheetState(() {
                                minutesBefore = min;
                                customMinController.clear();
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: customMinController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          hintText: 'أو حدد أي عدد دقائق مخصص (مثال: 25)',
                          suffixText: 'دقيقة',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed >= 0) {
                            setSheetState(() => minutesBefore = parsed);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Save Button
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00F2FE),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 20),
                    label: Text(
                      editAlarm == null ? 'حفظ وضبط المنبه ⏰' : 'حفظ التعديلات 💾',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: () async {
                      final title = titleController.text.trim().isEmpty ? 'منبه مدرسي' : titleController.text.trim();
                      final alarmId = editAlarm?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';

                      final newAlarm = AppAlarmModel(
                        id: alarmId,
                        title: title,
                        subtitle: subtitleController.text.trim(),
                        hour: selectedTime.hour,
                        minute: selectedTime.minute,
                        days: selectedDays.isNotEmpty ? selectedDays : ['الأحد'],
                        isEnabled: true,
                        type: AppAlarmType.custom,
                        minutesBefore: minutesBefore,
                        isVibrate: _vibrationEnabled,
                      );

                      if (editAlarm != null) {
                        _customAlarms.removeWhere((e) => e.id == editAlarm.id);
                        await NotificationService.cancelAlarmByKey(editAlarm.id);
                      }

                      _customAlarms.add(newAlarm);
                      _disabledAlarmIds.remove(alarmId);

                      await _saveCustomAlarms();
                      await _saveDisabledIds();

                      for (final day in newAlarm.days) {
                        await NotificationService.scheduleTimetableAlarm(
                          key: newAlarm.id,
                          dayName: day,
                          title: newAlarm.title,
                          body: newAlarm.subtitle,
                          hour: newAlarm.hour,
                          minute: newAlarm.minute,
                          minutesBefore: newAlarm.minutesBefore,
                          soundTone: _selectedTone,
                        );
                      }

                      Navigator.pop(ctx);
                      setState(() {
                        _buildUnifiedAlarmsList();
                      });

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم ضبط وتفعيل المنبه بنجاح! ⏰ (${newAlarm.nextOccurrenceArabicText})'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
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

  // Next Upcoming Alarm Info
  AppAlarmModel? get _nextUpcomingAlarm {
    final active = _allAlarms.where((a) => a.isEnabled).toList();
    if (active.isEmpty) return null;

    active.sort((a, b) {
      final da = a.durationUntilNextOccurrence?.inSeconds ?? 99999999;
      final db = b.durationUntilNextOccurrence?.inSeconds ?? 99999999;
      return da.compareTo(db);
    });

    return active.first;
  }

  // Filter alarms by selected day
  List<AppAlarmModel> _filterByDay(List<AppAlarmModel> list) {
    if (_selectedFilterDay == 'الكل') return list;
    return list.where((a) => a.days.contains(_selectedFilterDay)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final schoolAlarms = _allAlarms.where((a) => a.type == AppAlarmType.school).toList();
    final groupAlarms = _allAlarms.where((a) => a.type == AppAlarmType.group).toList();
    final customAlarms = _allAlarms.where((a) => a.type == AppAlarmType.custom).toList();

    final filteredAll = _filterByDay(_allAlarms);
    final filteredSchool = _filterByDay(schoolAlarms);
    final filteredGroups = _filterByDay(groupAlarms);
    final filteredCustom = _filterByDay(customAlarms);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children: [
            // 1. App Bar
            _buildAppBar(isDark),

            // 2. Central Live Digital Clock & Next Alarm Capsule
            _buildLiveClockBanner(isDark),

            // 3. Integrated Days Selector Bar (Horizontal week selector matching Timetable Groups)
            _buildIntegratedDaysBar(isDark),

            const SizedBox(height: 6),

            // 4. Category Filter Tabs
            _buildTabBar(
              isDark,
              filteredAll.length,
              filteredSchool.length,
              filteredGroups.length,
              filteredCustom.length,
            ),

            // 5. Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAlarmList(
                          filteredAll,
                          isDark,
                          _selectedFilterDay == 'الكل'
                              ? 'لا توجد منبهات حالياً'
                              : 'لا توجد منبهات مجدولة ليوم $_selectedFilterDay',
                        ),
                        _buildAlarmList(
                          filteredSchool,
                          isDark,
                          _selectedFilterDay == 'الكل'
                              ? 'لا توجد حصص مدرسية مضافة في الجدول'
                              : 'لا توجد حصص مدرسية ليوم $_selectedFilterDay',
                        ),
                        _buildAlarmList(
                          filteredGroups,
                          isDark,
                          _selectedFilterDay == 'الكل'
                              ? 'لا توجد مجموعات سنتر محددة بمواعيد'
                              : 'لا توجد مجموعات مجدولة ليوم $_selectedFilterDay',
                        ),
                        _buildAlarmList(
                          filteredCustom,
                          isDark,
                          _selectedFilterDay == 'الكل'
                              ? 'لا توجد منبهات مخصصة (اضغط ＋ لإضافة منبه)'
                              : 'لا توجد منبهات مخصصة ليوم $_selectedFilterDay',
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00F2FE),
        foregroundColor: Colors.black,
        elevation: 4,
        icon: const Icon(Icons.add_alarm_rounded, size: 22),
        label: const Text(
          'إضافة منبه جديد',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        onPressed: () => _openAddOrEditAlarmSheet(),
      ),
    );
  }

  Widget _buildAppBar(bool isDark) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.alarm_on_rounded, color: Color(0xFF00F2FE), size: 20),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'منبه الأكاديمية ⏰',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Custom Sound & Ringtone Selector 🎶
          IconButton(
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.music_note_rounded, color: Color(0xFF00F2FE), size: 21),
            tooltip: 'صوتيات ونغمات الموبايل 🎶',
            onPressed: _openSoundSelectorSheet,
          ),
          const SizedBox(width: 2),

          // Sync Timetable Alarms Button 🔄
          IconButton(
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.sync_rounded, color: Color(0xFF10B981), size: 21),
            tooltip: 'مزامنة وتفعيل حصص الجدول كمنبهات 🔄',
            onPressed: _syncTimetableAlarms,
          ),
          const SizedBox(width: 2),

          // In-App Alarm Settings ⚙️
          IconButton(
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.tune_rounded, color: Color(0xFFFBBF24), size: 20),
            tooltip: 'إعدادات المنبه الشاملة ⚙️',
            onPressed: _openAlarmSettingsSheet,
          ),
          const SizedBox(width: 2),

          // Clean Expired Button 🧹
          IconButton(
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF00F2FE), size: 19),
            tooltip: 'تنظيف المنبهات المنتهية 🧹',
            onPressed: () async {
              HapticFeedback.mediumImpact();
              final now = DateTime.now();
              final todayArabic = _getTodayName(now.weekday);
              final count = await AlarmService.cleanExpiredAlarms(
                todayPeriods: _schoolPeriods,
                todayGroups: _groups,
                todayArabic: todayArabic,
              );
              _loadAlarmsData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      count > 0 ? 'تم تنظيف وحذف $count منبهًا منتهيًا بنجاح 🧹' : 'لا توجد منبهات منتهية حالياً.',
                    ),
                    backgroundColor: const Color(0xFF10B981),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 2),

          // Delete All Alarms Button 🗑️
          IconButton(
            padding: const EdgeInsets.all(5),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 20),
            tooltip: 'حذف وتصفير كافة المنبهات 🗑️',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('حذف كافة المنبهات 🗑️', style: TextStyle(fontWeight: FontWeight.bold)),
                  content: const Text('هل أنت متأكد من رغبتك في حذف وإلغاء كافة المنبهات والتنبيهات بالكامل؟'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('نعم، حذف الكل'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                HapticFeedback.heavyImpact();
                final count = await AlarmService.dismissAllAlarms();
                _disabledAlarmIds.addAll(_allAlarms.map((a) => a.id));
                _customAlarms.clear();
                await _saveDisabledIds();
                await _saveCustomAlarms();
                _loadAlarmsData();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم حذف وإلغاء $count منبهًا وتنبيهًا بالكامل 🗑️'),
                      backgroundColor: const Color(0xFFEF4444),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveClockBanner(bool isDark) {
    final nextAlarm = _nextUpcomingAlarm;

    final hour12 = _currentTime.hour % 12 == 0 ? 12 : _currentTime.hour % 12;
    final hStr = hour12.toString().padLeft(2, '0');
    final mStr = _currentTime.minute.toString().padLeft(2, '0');
    final sStr = _currentTime.second.toString().padLeft(2, '0');
    final pStr = _currentTime.hour < 12 ? 'ص' : 'م';

    final dateStr = '${_getTodayName(_currentTime.weekday)}، ${_currentTime.day} ${_getMonthName(_currentTime.month)} ${_currentTime.year}';

    return Container(
      margin: const EdgeInsets.only(left: 14, right: 14, top: 8, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [Colors.white, const Color(0xFFF8FAFC)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$hStr:$mStr',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                ':$sStr',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00F2FE),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                pStr,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00F2FE),
                ),
              ),
            ],
          ),
          Text(
            dateStr,
            style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(height: 6),

          // Next Alarm Banner
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: nextAlarm != null
                        ? const Color(0xFF00F2FE).withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: nextAlarm != null
                          ? const Color(0xFF00F2FE).withValues(alpha: 0.35)
                          : Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        nextAlarm != null ? Icons.alarm_rounded : Icons.alarm_off_rounded,
                        size: 14,
                        color: nextAlarm != null ? const Color(0xFF00F2FE) : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          nextAlarm != null
                              ? '${nextAlarm.nextOccurrenceArabicText} (${nextAlarm.title})'
                              : 'لا توجد منبهات قادمة نشطة',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: nextAlarm != null
                                ? (isDark ? Colors.white : Colors.black87)
                                : Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
  }

  /// Integrated Day Rectangle (Identical style to Groups Timetable)
  Widget _buildIntegratedDaysBar(bool isDark) {
    final todayName = _getTodayName(DateTime.now().weekday);
    final isToday = _selectedFilterDay == todayName;
    final isAll = _selectedFilterDay == 'الكل';
    final count = _filterByDay(_allAlarms).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  isToday ? const Color(0xFF1E1B4B) : const Color(0xFF131B2E),
                  const Color(0xFF0F172A),
                ]
              : [
                  isToday ? const Color(0xFFFAF5FF) : const Color(0xFFF1F5F9),
                  Colors.white,
                ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday
              ? const Color(0xFFA855F7).withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: (isToday ? const Color(0xFFA855F7) : const Color(0xFF64748B))
                .withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Right side has Current Day info, Left side has "الأيام" button
          Row(
            children: [
              // Icon Badge (Click to return to today)
              InkWell(
                onTap: isToday
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        setState(() => _selectedFilterDay = todayName);
                      },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isToday
                          ? [const Color(0xFFA855F7), const Color(0xFF6366F1)]
                          : [const Color(0xFF0284C7), const Color(0xFF00F2FE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (isToday ? const Color(0xFFA855F7) : const Color(0xFF00F2FE))
                            .withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    isToday
                        ? Icons.stars_rounded
                        : (isAll ? Icons.all_inclusive_rounded : Icons.event_note_rounded),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Day Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isAll ? 'كافة أيام الأسبوع' : _selectedFilterDay,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Star badge to jump back to today
                        if (!isToday)
                          InkWell(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              setState(() => _selectedFilterDay = todayName);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('تمت العودة لمنبهات اليوم الحالي ($todayName) 🌟'),
                                  backgroundColor: const Color(0xFF10B981),
                                  duration: const Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFBBF24).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFBBF24).withValues(alpha: 0.7),
                                  width: 1,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.stars_rounded, color: Color(0xFFFBBF24), size: 12),
                                  SizedBox(width: 3),
                                  Text(
                                    'اليوم 🌟',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFBBF24),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF10B981), Color(0xFF059669)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, color: Colors.white, size: 10),
                                SizedBox(width: 3),
                                Text(
                                  'اليوم الحالي 🌟',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAll
                          ? '$count منبهات في كافة الأيام'
                          : '$count منبهات مجدولة ليوم $_selectedFilterDay',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              // Left Button: "الأيام" with arrow
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isDaysBarExpanded = !_isDaysBarExpanded);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isToday ? const Color(0xFFA855F7) : const Color(0xFF00F2FE)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (isToday ? const Color(0xFFA855F7) : const Color(0xFF00F2FE)).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 14,
                        color: isToday ? const Color(0xFFA855F7) : const Color(0xFF00F2FE),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'الأيام',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: isToday ? const Color(0xFFA855F7) : const Color(0xFF00F2FE),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isDaysBarExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: isToday ? const Color(0xFFA855F7) : const Color(0xFF00F2FE),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Horizontal Days Bar (Opens on click)
          if (_isDaysBarExpanded) ...[
            const SizedBox(height: 10),
            Container(
              height: 1,
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: _filterDaysList.map((day) {
                  final isSelected = _selectedFilterDay == day;
                  final isDayToday = day == todayName;
                  final dayAlarmsCount = day == 'الكل'
                      ? _allAlarms.length
                      : _allAlarms.where((a) => a.days.contains(day)).length;

                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedFilterDay = day);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(
                                  colors: isDayToday
                                      ? [const Color(0xFFA855F7), const Color(0xFF6366F1)]
                                      : [const Color(0xFF00F2FE), const Color(0xFF0284C7)],
                                )
                              : null,
                          color: isSelected
                              ? null
                              : (isDayToday
                                  ? const Color(0xFFA855F7).withValues(alpha: 0.12)
                                  : (isDark ? const Color(0xFF1E293B) : Colors.white)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? Colors.transparent
                                : (isDayToday
                                    ? const Color(0xFFA855F7).withValues(alpha: 0.4)
                                    : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1))),
                            width: isSelected ? 0 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: (isDayToday ? const Color(0xFFA855F7) : const Color(0xFF00F2FE))
                                        .withValues(alpha: 0.35),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1.5),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              day,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected || isDayToday ? FontWeight.w900 : FontWeight.bold,
                                color: isSelected
                                    ? (isDayToday ? Colors.white : Colors.black)
                                    : (isDayToday
                                        ? const Color(0xFFA855F7)
                                        : (isDark ? Colors.white : const Color(0xFF1E293B))),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isDayToday ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.15))
                                    : (isDark ? Colors.white12 : Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$dayAlarmsCount',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? (isDayToday ? Colors.white : Colors.black)
                                      : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDark, int allCount, int schoolCount, int groupCount, int customCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.black,
        unselectedLabelColor: isDark ? Colors.white70 : Colors.black54,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: const Color(0xFF00F2FE),
          borderRadius: BorderRadius.circular(10),
        ),
        labelStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        tabs: [
          Tab(text: 'الكل ($allCount)'),
          Tab(text: 'المدرسة ($schoolCount)'),
          Tab(text: 'الدروس ($groupCount)'),
          Tab(text: 'مخصصة ($customCount)'),
        ],
      ),
    );
  }

  Widget _buildAlarmList(List<AppAlarmModel> alarms, bool isDark, String emptyText) {
    if (alarms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.alarm_off_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.35)),
            const SizedBox(height: 10),
            Text(
              emptyText,
              style: const TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 14, right: 14, top: 8, bottom: 80),
      itemCount: alarms.length,
      itemBuilder: (ctx, index) {
        final alarm = alarms[index];
        return _buildAlarmCard(alarm, isDark);
      },
    );
  }

  /// Compact, sleek, and space-efficient alarm card
  Widget _buildAlarmCard(AppAlarmModel alarm, bool isDark) {
    final isEnabled = alarm.isEnabled;

    Color typeColor;
    IconData typeIcon;
    String typeLabel;
    switch (alarm.type) {
      case AppAlarmType.school:
        typeColor = const Color(0xFF00F2FE);
        typeIcon = Icons.school_rounded;
        typeLabel = 'مدرسة';
        break;
      case AppAlarmType.group:
        typeColor = const Color(0xFFA855F7);
        typeIcon = Icons.groups_rounded;
        typeLabel = 'مجموعة';
        break;
      case AppAlarmType.custom:
        typeColor = const Color(0xFF10B981);
        typeIcon = Icons.alarm_rounded;
        typeLabel = 'يدوي';
        break;
    }

    final isPlayingThis = _currentlyPlayingAudio == alarm.id;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isEnabled ? 1.0 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled
                ? (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1))
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
            width: isEnabled ? 1.2 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Time + Period + Type Badge + Minutes Badge + Spacer + Compact Switch
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Digital Time
                Text(
                  alarm.digitalTime,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  alarm.periodArabic,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(width: 8),

                // Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, size: 11, color: typeColor),
                      const SizedBox(width: 2.5),
                      Text(
                        typeLabel,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: typeColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),

                // Minutes Before Chip (Opens custom minute picker!)
                InkWell(
                  onTap: () => _showMinutesBeforePicker(alarm),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 10, color: Colors.amber),
                        const SizedBox(width: 2.5),
                        Text(
                          alarm.minutesBefore == 0 ? 'في الموعد' : 'قبل بـ ${alarm.minutesBefore} د',
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Switch Toggle
                Transform.scale(
                  scale: 0.82,
                  child: Switch.adaptive(
                    value: isEnabled,
                    activeTrackColor: const Color(0xFF00F2FE),
                    activeThumbColor: Colors.black,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) => _toggleAlarm(alarm, val),
                  ),
                ),
              ],
            ),

            // Row 2: Title & Subtitle + Next Occurrence
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alarm.title,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (alarm.subtitle.isNotEmpty)
                          Text(
                            alarm.subtitle,
                            style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (isEnabled)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        alarm.nextOccurrenceArabicText,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Row 3: Weekdays Bar + Quick Action Buttons (Test sound, Edit, Delete)
            Row(
              children: [
                // Weekdays mini squares
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(_weekdaysArabic.length, (i) {
                        final day = _weekdaysArabic[i];
                        final shortName = _weekdaysShort[i];
                        final isDayActive = alarm.days.contains(day);

                        return Container(
                          width: 19,
                          height: 19,
                          margin: const EdgeInsets.only(left: 2.5),
                          decoration: BoxDecoration(
                            color: isDayActive
                                ? (isEnabled ? const Color(0xFF00F2FE) : Colors.grey)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isDayActive
                                  ? (isEnabled ? const Color(0xFF00F2FE) : Colors.grey)
                                  : (isDark ? Colors.white24 : Colors.black12),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            shortName,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: isDayActive ? Colors.black : (isDark ? Colors.white38 : Colors.black38),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Sound preview / test button
                InkWell(
                  onTap: () {
                    if (isPlayingThis) {
                      _stopAudioPreview();
                    } else {
                      _playAudioPreview(
                        toneId: _customAudioPath == null ? _selectedTone : null,
                        filePath: _customAudioPath,
                        sourceKey: alarm.id,
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPlayingThis
                          ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                          : const Color(0xFFFBBF24).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isPlayingThis
                            ? const Color(0xFFEF4444)
                            : const Color(0xFFFBBF24).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlayingThis ? Icons.stop_rounded : Icons.volume_up_rounded,
                          size: 13,
                          color: isPlayingThis ? const Color(0xFFEF4444) : const Color(0xFFFBBF24),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isPlayingThis ? 'إيقاف' : 'تجربة',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: isPlayingThis ? const Color(0xFFEF4444) : const Color(0xFFFBBF24),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Edit (for custom alarms)
                if (alarm.type == AppAlarmType.custom) ...[
                  InkWell(
                    onTap: () => _openAddOrEditAlarmSheet(alarm),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF00F2FE)),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                // Delete
                InkWell(
                  onTap: () => _deleteAlarm(alarm),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFEF4444)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _getTodayName(int weekday) {
    switch (weekday) {
      case DateTime.sunday:
        return 'الأحد';
      case DateTime.monday:
        return 'الإثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      case DateTime.saturday:
        return 'السبت';
      default:
        return '';
    }
  }

  static String _getMonthName(int month) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }
}
