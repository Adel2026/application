import 'package:flutter/material.dart';

class AppLocale {
  static const Locale arabic = Locale('ar');
  static const Locale english = Locale('en');

  static bool isArabic(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ar';
  }

  static bool isEnglish(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'en';
  }

  static bool isArabicLocale(Locale locale) {
    return locale.languageCode == 'ar';
  }

  static String tr(BuildContext context, String key, {String? ar, String? en}) {
    final bool arLang = isArabic(context);
    if (arLang) {
      return ar ?? _arabicStrings[key] ?? key;
    } else {
      return en ?? _englishStrings[key] ?? key;
    }
  }

  static String get(String key, {required bool isArabic}) {
    if (isArabic) {
      return _arabicStrings[key] ?? key;
    } else {
      return _englishStrings[key] ?? key;
    }
  }

  /// Automatically localizes dynamic user data (group names, academic stages, schedules, grades, statuses)
  static String localizeData(BuildContext context, String? text) {
    if (text == null || text.isEmpty) return '';
    if (isArabic(context)) return text;
    return translateDataText(text);
  }

  static String translateDataText(String text) {
    if (text.isEmpty) return text;

    String s = text;

    // Common Instructor & Student Titles (Executed first to prevent partial replacements)
    s = s.replaceAll('أ. أحمد السيد', 'Prof. Ahmed El-Sayed');
    s = s.replaceAll('أ. أحمد', 'Prof. Ahmed');
    s = s.replaceAll('أ.د.', 'Prof. Dr.');
    s = s.replaceAll('د.', 'Dr.');
    s = s.replaceAll('أ.', 'Mr.');
    s = s.replaceAll('مدرس معتمد', 'Certified Teacher');
    s = s.replaceAll('معلم معتمد', 'Certified Instructor');
    s = s.replaceAll('محمد كريم الشريف', 'Mohamed Karim El-Sherif');
    s = s.replaceAll('أحمد محمود إبراهيم', 'Ahmed Mahmoud Ibrahim');
    s = s.replaceAll('علي حسن', 'Ali Hassan');
    s = s.replaceAll('سارة أحمد', 'Sara Ahmed');
    s = s.replaceAll('عمر خالد', 'Omar Khaled');

    // Common Group & Center Name Patterns
    s = s.replaceAll('سنتر أستاذي التعليمي', 'Edu Academy Hub');
    s = s.replaceAll('أكاديمية المستقبل التعليمية', 'Future Educational Academy');
    s = s.replaceAll('أكاديمية المستقبل', 'Future Academy');
    s = s.replaceAll('مجموعة المتفوقين', 'Honors / Top Achievers');
    s = s.replaceAll('مجموعة الأوائل', 'First Honors Cohort');
    s = s.replaceAll('مجموعة النخبة', 'Elite Cohort');
    s = s.replaceAll('مجموعة التميز', 'Excellence Group');
    s = s.replaceAll('مجموعة الفرسان', 'Champions Group');
    s = s.replaceAll('مجموعة العباقرة', 'Genius Cohort');
    s = s.replaceAll('مجموعة', 'Cohort / Group');

    // Academic Stages & Grades
    s = s.replaceAll('المرحلة الثانوية', 'High School (Secondary)');
    s = s.replaceAll('المرحلة الإعدادية', 'Middle School (Preparatory)');
    s = s.replaceAll('المرحلة الابتدائية', 'Elementary School (Primary)');
    s = s.replaceAll('الصف الأول الثانوي', 'Senior 1 (Grade 10)');
    s = s.replaceAll('الصف الثاني الثانوي', 'Senior 2 (Grade 11)');
    s = s.replaceAll('الصف الثالث الثانوي', 'Senior 3 (Grade 12)');
    s = s.replaceAll('1 ث', 'G10 (Senior 1)');
    s = s.replaceAll('2 ث', 'G11 (Senior 2)');
    s = s.replaceAll('3 ث', 'G12 (Senior 3)');
    s = s.replaceAll('1 ثانوى', 'G10 (Senior 1)');
    s = s.replaceAll('2 ثانوى', 'G11 (Senior 2)');
    s = s.replaceAll('3 ثانوى', 'G12 (Senior 3)');
    s = s.replaceAll('1 ثانوي', 'G10 (Senior 1)');
    s = s.replaceAll('2 ثانوي', 'G11 (Senior 2)');
    s = s.replaceAll('3 ثانوي', 'G12 (Senior 3)');
    s = s.replaceAll('الصف الأول الإعدادي', 'Prep 1 (Grade 7)');
    s = s.replaceAll('الصف الثاني الإعدادي', 'Prep 2 (Grade 8)');
    s = s.replaceAll('الصف الثالث الإعدادي', 'Prep 3 (Grade 9)');
    s = s.replaceAll('1 ع', 'Grade 7');
    s = s.replaceAll('2 ع', 'Grade 8');
    s = s.replaceAll('3 ع', 'Grade 9');
    s = s.replaceAll('1 إعدادى', 'Grade 7');
    s = s.replaceAll('2 إعدادى', 'Grade 8');
    s = s.replaceAll('3 إعدادى', 'Grade 9');
    s = s.replaceAll('1 إعدادي', 'Grade 7');
    s = s.replaceAll('2 إعدادي', 'Grade 8');
    s = s.replaceAll('3 إعدادي', 'Grade 9');
    s = s.replaceAll('الصف الرابع الابتدائي', 'Grade 4');
    s = s.replaceAll('الصف الخامس الابتدائي', 'Grade 5');
    s = s.replaceAll('الصف السادس الابتدائي', 'Grade 6');
    s = s.replaceAll('الصف الرابع', 'Grade 4');
    s = s.replaceAll('الصف الخامس', 'Grade 5');
    s = s.replaceAll('الصف السادس', 'Grade 6');
    s = s.replaceAll('الصف الأول', 'Grade 1');
    s = s.replaceAll('الصف الثاني', 'Grade 2');
    s = s.replaceAll('الصف الثالث', 'Grade 3');

    // Subjects
    s = s.replaceAll('الرياضيات والفيزياء', 'Math & Physics');
    s = s.replaceAll('الرياضيات', 'Mathematics');
    s = s.replaceAll('الفيزياء', 'Physics');
    s = s.replaceAll('الكيمياء', 'Chemistry');
    s = s.replaceAll('الأحياء', 'Biology');
    s = s.replaceAll('العلوم', 'Science');
    s = s.replaceAll('اللغة العربية', 'Arabic Language');
    s = s.replaceAll('اللغة الإنجليزية', 'English Language');
    s = s.replaceAll('الدراسات الاجتماعية', 'Social Studies');
    s = s.replaceAll('الدراسات', 'Social Studies');
    s = s.replaceAll('التاريخ', 'History');
    s = s.replaceAll('الجغرافيا', 'Geography');
    s = s.replaceAll('الفلسفة والمنطق', 'Philosophy & Logic');
    s = s.replaceAll('الفلسفة', 'Philosophy');
    s = s.replaceAll('الجيولوجيا', 'Geology');
    s = s.replaceAll('الفرنساوي', 'French');
    s = s.replaceAll('الإيطالي', 'Italian');
    s = s.replaceAll('الألماني', 'German');

    // Days & Schedule Timing
    s = s.replaceAll('السبت والأربعاء', 'Sat & Wed');
    s = s.replaceAll('الأحد والثلاثاء', 'Sun & Tue');
    s = s.replaceAll('الاثنين والخميس', 'Mon & Thu');
    s = s.replaceAll('السبت والأحد', 'Sat & Sun');
    s = s.replaceAll('الثلاثاء والجمعة', 'Tue & Fri');
    s = s.replaceAll('الجمعة', 'Friday');
    s = s.replaceAll('السبت', 'Saturday');
    s = s.replaceAll('الأحد', 'Sunday');
    s = s.replaceAll('الاثنين', 'Monday');
    s = s.replaceAll('الثلاثاء', 'Tuesday');
    s = s.replaceAll('الأربعاء', 'Wednesday');
    s = s.replaceAll('الخميس', 'Thursday');

    // Specific Schedule Timing (Safe regex matching only digits with time symbols)
    s = s.replaceAllMapped(RegExp(r'(\d{1,2}:\d{2})\s*م'), (m) => '${m[1]} PM');
    s = s.replaceAllMapped(RegExp(r'(\d{1,2}:\d{2})\s*ص'), (m) => '${m[1]} AM');
    s = s.replaceAllMapped(RegExp(r'(\d{1,2})\s*م\b'), (m) => '${m[1]} PM');
    s = s.replaceAllMapped(RegExp(r'(\d{1,2})\s*ص\b'), (m) => '${m[1]} AM');

    // Statuses & Attendance
    s = s.replaceAll('حاضر في الموعد', 'Present on Time');
    s = s.replaceAll('حاضر', 'Present');
    s = s.replaceAll('غائب', 'Absent');
    s = s.replaceAll('متأخر', 'Late');
    s = s.replaceAll('بعذر', 'Excused');
    s = s.replaceAll('سداد شهري', 'Monthly Subscription');
    s = s.replaceAll('سداد بالحصة', 'Per Session');
    s = s.replaceAll('سداد', 'Paid');
    s = s.replaceAll('مستحق', 'Due');
    s = s.replaceAll('خالص', 'Settled');
    s = s.replaceAll('طالبة', 'Students');
    s = s.replaceAll('طلاب', 'Students');
    s = s.replaceAll('طالب', 'Students');
    s = s.replaceAll('حصص', 'Sessions');
    s = s.replaceAll('حصة', 'Session');
    s = s.replaceAll('ج.م', 'EGP');
    s = s.replaceAll('ج/شهر', 'EGP/mo');

    return s;
  }

  // Comprehensive natural idiomatic English & Arabic mapping
  static final Map<String, String> _arabicStrings = {
    // Navigation / Modules
    'dashboard': 'الرئيسية',
    'students': 'الطلاب',
    'groups': 'المجموعات',
    'attendance': 'التحضير',
    'finances': 'المالية',
    'curriculum': 'المناهج',
    'exams': 'الاختبارات',
    'scanner': 'ماسح QR',
    'whatsapp': 'واتساب',
    'reports': 'التقارير',
    'settings': 'الإعدادات',
    'menu': 'القائمة',
    'quick_scan': 'مسح سريع',

    // Common Actions
    'save': 'حفظ',
    'cancel': 'إلغاء',
    'delete': 'حذف',
    'edit': 'تعديل',
    'add': 'إضافة',
    'search': 'بحث',
    'confirm': 'تأكيد',
    'back': 'رجوع',
    'close': 'إغلاق',
    'done': 'تم',
    'retry': 'إعادة المحاولة',
    'export': 'تصدير',
    'import': 'استيراد',
    'share': 'مشاركة',
    'send': 'إرسال',
    'details': 'التفاصيل',
    'select_all': 'تحديد الكل',
    'clear': 'مسح',
    'active': 'نشط',
    'inactive': 'غير نشط',
    'present': 'حاضر',
    'absent': 'غائب',
    'late': 'متأخر',
    'excused': 'بعذر',
    'classes': 'حصص',
    'overview': 'نظرة عامة',

    // Dashboard
    'welcome_back': 'أهلاً بك،',
    'certified_teacher': 'مدرس معتمد',
    'total_students': 'عدد الطلاب',
    'today_attendance': 'نسبة الحضور',
    'today_revenue': 'الأرباح',
    'total_dues': 'إجمالي المتأخرات',
    'active_students': 'إجمالي الطلاب النشطين',
    'active_students_sub': 'المسجلين حالياً بالمجموعات الدراسية',
    'today_sessions': 'حصص اليوم',
    'no_sessions_today': 'لا توجد حصص مجدولة اليوم',
    'relax_day': 'يوم راحة أو مراجعة ذاتية، يمكنك الاطلاع على كشف كل المجموعات.',
    'financial_overview': 'مؤشر التدفق المالي والتحصيل',
    'cash_liquidity': 'إجمالي التحصيل والسيولة النقدية',
    'collected': 'المحصل',
    'overdue': 'المتأخرات',
    'quick_attendance_action': 'تحضير ➔',
    'whatsapp_hub_title': 'مركز الإرسال السريع لواتساب',
    'whatsapp_hub_sub': 'تنبيهات أولياء الأمور والطلاب',
    'view_all_messages': 'الرسائل ➔',
    'absent_alert': '📢 تنبيه غياب اليوم',
    'session_reminder': '⏰ تذكير بموعد الحصة',
    'payment_alert': '💳 إشعار سداد المصروفات',
    'excellence_congrats': '🏆 تهنئة المتفوقين',
    'recent_receipts': 'أحدث إيصالات القبض والعمليات المالية',
    'view_all': 'عرض الكل ➔',
    'all_receipts_recorded': 'تم تسجيل كافة العمليات النقدية والاشتراكات بسجلات السنتر بنجاح',
    'curriculum_progress': 'المناهج الدراسية',
    'completed_lessons': 'درس مكتمل',
    'daily_todos': 'قائمة المهام اليومية',
    'quick_notes': 'ملاحظات وتذكيرات سريعة للمعلم',
    'all_groups_schedule': 'جدول المجموعات الكامل',

    // Groups & Schedule
    'schedule': 'الجدول القادم',
    'add_group': 'إضافة مجموعة',
    'edit_group': 'تعديل مجموعة',
    'group_name': 'اسم المجموعة',
    'stage': 'المرحلة الدراسية',
    'grade': 'الصف الدراسي',
    'room': 'القاعة',
    'monthly_price': 'الاشتراك الشهري',
    'session_price': 'سعر الحصة',
    'students_count': 'عدد الطلاب',
    'no_groups': 'لا توجد مجموعات بعد',

    // Attendance Guard
    'timing_guard_title': 'تنبيه دقة موعد التحضير',
    'timing_guard_desc': 'غير مسموح ببدء التحضير إلا قبل موعد المجموعة بـ 5 دقائق فقط لضمان دقة الرصد.',
    'session_starts_at': 'موعد الحصة',
    'minutes_remaining': 'متبقي على إتاحة التحضير',
    'understood': 'حسناً، فهمت',

    // Settings
    'language': 'اللغة',
    'language_desc': 'اختر لغة واجهة النظام',
    'arabic': 'العربية',
    'english': 'English',
    'theme_mode': 'وضع المظهر',
    'dark_mode': 'الوضع الليلي',
    'light_mode': 'الوضع الفاتح',
    'system_mode': 'تلقائي (حسب النظام)',
    'fullscreen_mode': 'وضع ملء الشاشة الفائق',
    'fullscreen_desc': 'إخفاء شريط الساعة والشبكة لتوفير أقصى مساحة',
    'center_profile': 'بيانات المركز',
    'teacher_profile': 'الملف الشخصي',
    'appearance': 'المظهر',
    'cloud_backup': 'النسخ السحابي',
    'excel_import': 'إكسل',
    'whatsapp_gateway': 'بوابة واتساب',
    'restore_default_order': 'استعادة الترتيب الافتراضي',
    'reorder_tabs': 'ترتيب التبويبات',
    'drag_to_reorder': 'اسحب العناصر بالترتيب الذي تفضله',
  };

  static final Map<String, String> _englishStrings = {
    // Navigation / Modules
    'dashboard': 'Home',
    'students': 'Students',
    'groups': 'Classes',
    'attendance': 'Roll Call',
    'finances': 'Finances',
    'curriculum': 'Syllabus',
    'exams': 'Assessments',
    'scanner': 'QR Scanner',
    'whatsapp': 'WhatsApp',
    'reports': 'Analytics',
    'settings': 'Settings',
    'menu': 'Menu',
    'quick_scan': 'Quick Scan',

    // Common Actions
    'save': 'Save',
    'cancel': 'Cancel',
    'delete': 'Delete',
    'edit': 'Edit',
    'add': 'Add',
    'search': 'Search',
    'confirm': 'Confirm',
    'back': 'Back',
    'close': 'Close',
    'done': 'Done',
    'retry': 'Retry',
    'export': 'Export',
    'import': 'Import',
    'share': 'Share',
    'send': 'Send',
    'details': 'Details',
    'select_all': 'Select All',
    'clear': 'Clear',
    'active': 'Active',
    'inactive': 'Inactive',
    'present': 'Present',
    'absent': 'Absent',
    'late': 'Late',
    'excused': 'Excused',
    'classes': 'Classes',
    'overview': 'Overview',

    // Dashboard
    'welcome_back': 'Welcome back,',
    'certified_teacher': 'Certified Instructor',
    'total_students': 'Students',
    'today_attendance': 'Attendance',
    'today_revenue': 'Earnings',
    'total_dues': 'Outstanding Dues',
    'active_students': 'Active Enrolled Students',
    'active_students_sub': 'Currently enrolled across academic cohorts',
    'today_sessions': "Today's Sessions",
    'no_sessions_today': 'No sessions scheduled for today',
    'relax_day': 'Rest day or self-review. You can view all academic groups.',
    'financial_overview': 'Cashflow & Revenue Rate',
    'cash_liquidity': 'Total collections & net liquidity',
    'collected': 'Collected',
    'overdue': 'Overdue',
    'quick_attendance_action': 'Check-in ➔',
    'whatsapp_hub_title': 'WhatsApp Dispatch Center',
    'whatsapp_hub_sub': 'Automated parent & student notifications',
    'view_all_messages': 'Messages ➔',
    'absent_alert': '📢 Absent Today Notice',
    'session_reminder': '⏰ Class Time Reminder',
    'payment_alert': '💳 Fee Settlement Notice',
    'excellence_congrats': '🏆 Honors Congratulations',
    'recent_receipts': 'Recent Payment Vouchers & Receipts',
    'view_all': 'View All ➔',
    'all_receipts_recorded': 'All cash receipts and subscriptions successfully registered',
    'curriculum_progress': 'Curriculum & Units',
    'completed_lessons': 'Lessons Completed',
    'daily_todos': 'Daily Priorities & Checklist',
    'quick_notes': 'Teacher Quick Notes & Reminders',
    'all_groups_schedule': 'Master Timetable & Capacity',

    // Groups & Schedule
    'schedule': 'Upcoming Schedule',
    'add_group': 'New Class',
    'edit_group': 'Edit Class',
    'group_name': 'Class Name',
    'stage': 'Education Level',
    'grade': 'Academic Grade',
    'room': 'Hall / Room',
    'monthly_price': 'Monthly Fee',
    'session_price': 'Per-Session Fee',
    'students_count': 'Enrolled Students',
    'no_groups': 'No classes created yet',

    // Attendance Guard
    'timing_guard_title': 'Session Timing Verification',
    'timing_guard_desc': 'Attendance check-in opens strictly 5 minutes prior to session start time.',
    'session_starts_at': 'Session Time',
    'minutes_remaining': 'Time until check-in opens',
    'understood': 'Understood',

    // Settings
    'language': 'Language',
    'language_desc': 'Select interface language',
    'arabic': 'العربية',
    'english': 'English',
    'theme_mode': 'Appearance Theme',
    'dark_mode': 'Dark Theme',
    'light_mode': 'Light Theme',
    'system_mode': 'System Match',
    'fullscreen_mode': 'Ultra Fullscreen Mode',
    'fullscreen_desc': 'Hide status bar & clock for maximum workspace',
    'center_profile': 'Center Profile',
    'teacher_profile': 'Instructor Profile',
    'appearance': 'Appearance',
    'cloud_backup': 'Cloud Sync',
    'excel_import': 'Excel Tools',
    'whatsapp_gateway': 'WhatsApp Gateway',
    'restore_default_order': 'Restore Default Order',
    'reorder_tabs': 'Reorder Navigation Tabs',
    'drag_to_reorder': 'Drag items into your preferred sequence',
  };
}

extension AppLocaleExtension on String {
  String tr(BuildContext context) => AppLocale.tr(context, this);
  String trData(BuildContext context) => AppLocale.localizeData(context, this);
}
