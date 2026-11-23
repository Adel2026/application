import 'dart:convert';

enum AppAlarmType {
  school, // حصة جدول مدرسي
  group,  // مجموعة دروس / سنتر
  custom, // منبه يدوي مخصص
}

class AppAlarmModel {
  final String id;
  final String title;
  final String subtitle;
  final int hour;
  final int minute;
  final List<String> days; // e.g. ['الأحد', 'الإثنين']
  final bool isEnabled;
  final AppAlarmType type;
  final int minutesBefore; // 0, 5, 10, 15 minutes before
  final bool isVibrate;
  final String? sourceId;

  const AppAlarmModel({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.hour,
    required this.minute,
    required this.days,
    this.isEnabled = true,
    this.type = AppAlarmType.custom,
    this.minutesBefore = 0,
    this.isVibrate = true,
    this.sourceId,
  });

  AppAlarmModel copyWith({
    String? id,
    String? title,
    String? subtitle,
    int? hour,
    int? minute,
    List<String>? days,
    bool? isEnabled,
    AppAlarmType? type,
    int? minutesBefore,
    bool? isVibrate,
    String? sourceId,
  }) {
    return AppAlarmModel(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      days: days ?? this.days,
      isEnabled: isEnabled ?? this.isEnabled,
      type: type ?? this.type,
      minutesBefore: minutesBefore ?? this.minutesBefore,
      isVibrate: isVibrate ?? this.isVibrate,
      sourceId: sourceId ?? this.sourceId,
    );
  }

  /// Formatted digital time string like "07:45"
  String get digitalTime {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final hStr = h.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr';
  }

  /// AM / PM string in Arabic ("ص" / "م")
  String get periodArabic => hour < 12 ? 'ص' : 'م';

  /// Human-readable time with AM/PM
  String get formattedTime => '$digitalTime $periodArabic';

  /// Formatted days label
  String get daysSummary {
    if (days.isEmpty) return 'مرة واحدة';
    if (days.length == 7) return 'كل يوم';
    const schoolWeekdays = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
    if (days.length == 5 && schoolWeekdays.every(days.contains)) {
      return 'أيام المدرسة (الأحد - الخميس)';
    }
    return days.join('، ');
  }

  /// Calculates duration until next occurrence
  Duration? get durationUntilNextOccurrence {
    if (!isEnabled) return null;
    final now = DateTime.now();

    // If no repeating days, check today / tomorrow
    if (days.isEmpty) {
      var nextTime = DateTime(now.year, now.month, now.day, hour, minute);
      if (nextTime.isBefore(now)) {
        nextTime = nextTime.add(const Duration(days: 1));
      }
      return nextTime.difference(now);
    }

    // Check next 7 days for matching day
    for (int i = 0; i < 7; i++) {
      final candidateDate = now.add(Duration(days: i));
      final candidateDayName = _weekdayToArabic(candidateDate.weekday);
      if (days.contains(candidateDayName)) {
        final target = DateTime(
          candidateDate.year,
          candidateDate.month,
          candidateDate.day,
          hour,
          minute,
        );
        if (target.isAfter(now)) {
          return target.difference(now);
        }
      }
    }
    // If today matched but time passed, check in 7 days
    return null;
  }

  /// Relative time description like "رنين خلال ساعتين و 15 دقيقة"
  String get nextOccurrenceArabicText {
    final diff = durationUntilNextOccurrence;
    if (diff == null) return isEnabled ? 'سيرن في الموعد القادم' : 'متوقف مؤقتاً';

    final totalMinutes = diff.inMinutes;
    if (totalMinutes <= 0) return 'الآن';
    if (totalMinutes < 60) {
      return 'رنين خلال $totalMinutes دقيقة';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) {
      return 'رنين خلال $hours ساعة';
    }
    return 'رنين خلال $hours ساعة و $minutes دقيقة';
  }

  static String _weekdayToArabic(int weekday) {
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'hour': hour,
      'minute': minute,
      'days': days,
      'isEnabled': isEnabled,
      'type': type.name,
      'minutesBefore': minutesBefore,
      'isVibrate': isVibrate,
      'sourceId': sourceId,
    };
  }

  factory AppAlarmModel.fromMap(Map<String, dynamic> map) {
    return AppAlarmModel(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      subtitle: map['subtitle']?.toString() ?? '',
      hour: int.tryParse(map['hour']?.toString() ?? '0') ?? 0,
      minute: int.tryParse(map['minute']?.toString() ?? '0') ?? 0,
      days: (map['days'] as List?)?.map((e) => e.toString()).toList() ?? [],
      isEnabled: map['isEnabled'] == true || map['isEnabled'] == 1 || map['isEnabled'] == 'true',
      type: AppAlarmType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => AppAlarmType.custom,
      ),
      minutesBefore: int.tryParse(map['minutesBefore']?.toString() ?? '0') ?? 0,
      isVibrate: map['isVibrate'] != false,
      sourceId: map['sourceId']?.toString(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory AppAlarmModel.fromJson(String source) => AppAlarmModel.fromMap(jsonDecode(source));
}
