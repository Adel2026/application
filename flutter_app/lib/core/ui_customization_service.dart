import 'dart:convert';
import 'package:flutter/material.dart';
import 'database/database_service.dart';

// ==============================================================================
// 1. Navigation Item Definition (Bottom Navigation Dock)
// ==============================================================================
class NavItemDef {
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color? badgeColor;
  bool isEnabled;

  bool get enabled => isEnabled;
  set enabled(bool val) => isEnabled = val;
  String get title => label;

  NavItemDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badgeColor,
    this.isEnabled = true,
  });

  NavItemDef copyWith({
    String? id,
    String? label,
    IconData? icon,
    IconData? activeIcon,
    Color? badgeColor,
    bool? enabled,
    bool? isEnabled,
  }) {
    return NavItemDef(
      id: id ?? this.id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      activeIcon: activeIcon ?? this.activeIcon,
      badgeColor: badgeColor ?? this.badgeColor,
      isEnabled: enabled ?? isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'isEnabled': isEnabled,
      };
}

// ==============================================================================
// 2. Header Action Definition (Top AppBar Shortcuts Store)
// ==============================================================================
class HeaderActionDef {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  bool isEnabled;

  HeaderActionDef({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    this.isEnabled = true,
  });

  HeaderActionDef copyWith({
    String? id,
    String? title,
    String? description,
    IconData? icon,
    Color? iconColor,
    bool? isEnabled,
  }) {
    return HeaderActionDef(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      iconColor: iconColor ?? this.iconColor,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'isEnabled': isEnabled,
      };
}

// ==============================================================================
// 3. Dashboard Widget Definition (Full Matching Widget Store)
// ==============================================================================
class DashboardWidgetDef {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String category; // 'all', 'overview', 'kpis', 'schedules', 'finances', 'tools'
  bool isEnabled;
  String size; // 'full' (100%), 'half' (50%), 'compact' (مدمج)

  bool get enabled => isEnabled;
  set enabled(bool val) => isEnabled = val;

  DashboardWidgetDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.category = 'overview',
    this.isEnabled = true,
    this.size = 'full',
  });

  DashboardWidgetDef copyWith({
    String? id,
    String? title,
    String? subtitle,
    IconData? icon,
    Color? iconColor,
    String? category,
    bool? enabled,
    bool? isEnabled,
    String? size,
  }) {
    return DashboardWidgetDef(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      iconColor: iconColor ?? this.iconColor,
      category: category ?? this.category,
      isEnabled: enabled ?? isEnabled ?? this.isEnabled,
      size: size ?? this.size,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'isEnabled': isEnabled,
        'size': size,
      };
}

// ==============================================================================
// 4. UI Customization Service & Master Catalog
// ==============================================================================
class UiCustomizationService {
  static const String keyBottomNavHidden = 'bottom_nav_hidden';
  static const String keyBottomNavItems = 'bottom_nav_items_order_v2';
  static const String keyDashboardWidgets = 'dashboard_widgets_order_v3';
  static const String keyHeaderActions = 'header_actions_order_v1';

  static List<NavItemDef> get defaultNavItems => getMasterNavItems();
  static List<DashboardWidgetDef> get defaultDashboardWidgets => getMasterDashboardWidgets();
  static List<HeaderActionDef> get defaultHeaderActions => getMasterHeaderActions();

  // --------------------------------------------------------------------------
  // Default Navigation Definitions (All 10 app modules)
  // --------------------------------------------------------------------------
  static List<NavItemDef> getMasterNavItems() {
    return [
      NavItemDef(
        id: 'dashboard',
        label: 'الرئيسية',
        icon: Icons.grid_view_outlined,
        activeIcon: Icons.grid_view_rounded,
        isEnabled: true,
      ),
      NavItemDef(
        id: 'settings',
        label: 'الإعدادات',
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        badgeColor: const Color(0xFF64748B),
        isEnabled: true,
      ),
      NavItemDef(
        id: 'groups',
        label: 'المجموعات',
        icon: Icons.groups_outlined,
        activeIcon: Icons.groups_rounded,
        isEnabled: false,
      ),
      NavItemDef(
        id: 'attendance',
        label: 'تحضير اليوم',
        icon: Icons.fact_check_outlined,
        activeIcon: Icons.fact_check_rounded,
        badgeColor: const Color(0xFF0D9488),
        isEnabled: false,
      ),
      NavItemDef(
        id: 'finances',
        label: 'الماليات',
        icon: Icons.account_balance_wallet_outlined,
        activeIcon: Icons.account_balance_wallet_rounded,
        badgeColor: const Color(0xFF059669),
        isEnabled: false,
      ),
      NavItemDef(
        id: 'curriculum',
        label: 'المناهج',
        icon: Icons.menu_book_outlined,
        activeIcon: Icons.menu_book_rounded,
        badgeColor: const Color(0xFFEA580C),
        isEnabled: false,
      ),
      NavItemDef(
        id: 'exams',
        label: 'الاختبارات',
        icon: Icons.military_tech_outlined,
        activeIcon: Icons.military_tech_rounded,
        badgeColor: const Color(0xFF7C3AED),
        isEnabled: false,
      ),
      NavItemDef(
        id: 'scanner',
        label: 'ماسح QR',
        icon: Icons.qr_code_scanner_outlined,
        activeIcon: Icons.qr_code_scanner_rounded,
        badgeColor: const Color(0xFF0284C7),
        isEnabled: false,
      ),
      NavItemDef(
        id: 'whatsapp',
        label: 'واتساب',
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        badgeColor: const Color(0xFF25D366),
        isEnabled: true,
      ),
      NavItemDef(
        id: 'reports',
        label: 'التقارير',
        icon: Icons.analytics_outlined,
        activeIcon: Icons.analytics_rounded,
        isEnabled: false,
      ),
      NavItemDef(
        id: 'students',
        label: 'الطلاب',
        icon: Icons.school_outlined,
        activeIcon: Icons.school_rounded,
        isEnabled: false,
      ),
      NavItemDef(
        id: 'menu',
        label: 'القائمة',
        icon: Icons.menu_rounded,
        activeIcon: Icons.menu_open_rounded,
        badgeColor: const Color(0xFF38BDF8),
        isEnabled: true,
      ),
    ];
  }

  // --------------------------------------------------------------------------
  // Header Action Shortcuts Catalog
  // --------------------------------------------------------------------------
  static List<HeaderActionDef> getMasterHeaderActions() {
    return [
      HeaderActionDef(
        id: 'fullscreen_nav',
        title: 'إخفاء / إظهار الشريط السفلي',
        description: 'زر سريع لتبديل الشريط السفلي وتوسيع الشاشة',
        icon: Icons.fullscreen_rounded,
        iconColor: const Color(0xFF3B82F6),
        isEnabled: true,
      ),
      HeaderActionDef(
        id: 'qr_scanner',
        title: 'ماسح QR والباركود',
        description: 'فتح كاميرا المسح الفوري لتحضير الطلاب بالأكواد',
        icon: Icons.qr_code_scanner_rounded,
        iconColor: const Color(0xFF0D9488),
        isEnabled: true,
      ),
      HeaderActionDef(
        id: 'add_student',
        title: 'إضافة طالب سريع',
        description: 'فتح نافذة إضافة طالب جديد فورياً من أي مكان',
        icon: Icons.person_add_alt_1_rounded,
        iconColor: const Color(0xFF2563EB),
        isEnabled: true,
      ),
      HeaderActionDef(
        id: 'add_group',
        title: 'إضافة مجموعة جديدة',
        description: 'اختصار سريع لإنشاء وضبط مجموعة دراسية',
        icon: Icons.group_add_rounded,
        iconColor: const Color(0xFF7C3AED),
        isEnabled: false,
      ),
      HeaderActionDef(
        id: 'theme_toggle',
        title: 'تبديل المظهر الليلي والفاتح',
        description: 'تحويل ثيم التطبيق بين النهاري والليلي بلمسة',
        icon: Icons.brightness_4_rounded,
        iconColor: const Color(0xFFF59E0B),
        isEnabled: true,
      ),
      HeaderActionDef(
        id: 'whatsapp_hub',
        title: 'مركز رسائل واتساب',
        description: 'فتح شاشة إرسال التنبيهات المباشرة لأولياء الأمور',
        icon: Icons.chat_rounded,
        iconColor: const Color(0xFF25D366),
        isEnabled: false,
      ),
      HeaderActionDef(
        id: 'today_attendance',
        title: 'تحضير اليوم الفوري',
        description: 'انتقال سريع لكشف حضور وغياب حصص اليوم',
        icon: Icons.fact_check_rounded,
        iconColor: const Color(0xFF059669),
        isEnabled: false,
      ),
      HeaderActionDef(
        id: 'settings',
        title: 'إعدادات النظام والسنتر',
        description: 'فتح لوحة التحكم والتخصيصات والنسخ الاحتياطي',
        icon: Icons.settings_rounded,
        iconColor: const Color(0xFF64748B),
        isEnabled: true,
      ),
    ];
  }

  // --------------------------------------------------------------------------
  // Full Widget Store Catalog (Matching the exact images and categories)
  // --------------------------------------------------------------------------
  static List<DashboardWidgetDef> getMasterDashboardWidgets() {
    return [
      // 1. البانر الترحيبي وإجراءات الانطلاق السريع
      DashboardWidgetDef(
        id: 'hero_launchpad',
        title: 'البانر الترحيبي وإجراءات الانطلاق السريع',
        subtitle: 'ترحيب المعلم، معلومات اليوم، وأزرار التحضير والقبض الفورية',
        icon: Icons.rocket_launch_rounded,
        iconColor: const Color(0xFF6366F1),
        category: 'overview',
        isEnabled: true,
      ),

      // 2. شبكة بينتو الرقمية الذكية (Design 2: Bento Grid Dashboard)
      DashboardWidgetDef(
        id: 'bento_grid_hub',
        title: 'شبكة بينتو الرقمية الذكية (Bento Grid)',
        subtitle: 'تصميم بينتو العصري: العداد الدائري، التحضير الفوري المتوهج، وجدول الحصص التفاعلي',
        icon: Icons.dashboard_customize_rounded,
        iconColor: const Color(0xFF00F2FE),
        category: 'overview',
        isEnabled: true,
        size: 'full',
      ),

      // 2. مجموعة بطاقات المؤشرات الستة الموحدة
      DashboardWidgetDef(
        id: 'unified_six_kpis',
        title: 'مجموعة بطاقات المؤشرات الستة الموحدة',
        subtitle: 'الطلاب، الحصص، الإيرادات، المتأخرات، الأرباح، والاختبارات مجمعة',
        icon: Icons.bar_chart_rounded,
        iconColor: const Color(0xFF10B981),
        category: 'kpis',
        isEnabled: true,
      ),

      // 3. بطاقة إجمالي الطلاب النشطين
      DashboardWidgetDef(
        id: 'active_students_card',
        title: 'بطاقة إجمالي الطلاب النشطين',
        subtitle: 'عدد الطلاب النشطين والمسجلين في المجموعات مع قفزة سريعة',
        icon: Icons.groups_rounded,
        iconColor: const Color(0xFF3B82F6),
        category: 'kpis',
        isEnabled: false,
      ),

      // 4. بطاقة حصص اليوم ومعدل الحضور
      DashboardWidgetDef(
        id: 'today_classes_attendance',
        title: 'بطاقة حصص اليوم ومعدل الحضور',
        subtitle: 'عدد حصص اليوم مع نسبة الحضور والغياب الحالية',
        icon: Icons.calendar_month_rounded,
        iconColor: const Color(0xFFEF4444),
        category: 'schedules',
        isEnabled: false,
      ),

      // 5. بطاقة الإيرادات والتحصيلات للشهر
      DashboardWidgetDef(
        id: 'monthly_revenue_card',
        title: 'بطاقة الإيرادات والتحصيلات للشهر',
        subtitle: 'إجمالي المحصل لشهر اليوم مع عدد سندات القبض',
        icon: Icons.trending_up_rounded,
        iconColor: const Color(0xFF059669),
        category: 'finances',
        isEnabled: false,
      ),

      // 6. بطاقة المتأخرات والمبالغ المعلقة
      DashboardWidgetDef(
        id: 'pending_debt_card',
        title: 'بطاقة المتأخرات والمبالغ المعلقة',
        subtitle: 'إجمالي المتبقي على الطلاب مع عدد المطالبين بالسداد',
        icon: Icons.warning_amber_rounded,
        iconColor: const Color(0xFFF59E0B),
        category: 'finances',
        isEnabled: false,
      ),

      // 7. بطاقة صافي الأرباح والمصروفات
      DashboardWidgetDef(
        id: 'net_profit_expenses_card',
        title: 'بطاقة صافي الأرباح والمصروفات',
        subtitle: 'صافي الأرباح بعد خصم المصروفات التشغيلية',
        icon: Icons.payments_rounded,
        iconColor: const Color(0xFF14B8A6),
        category: 'finances',
        isEnabled: false,
      ),

      // 8. بطاقة الاختبارات والتقييمات
      DashboardWidgetDef(
        id: 'exams_assessments_card',
        title: 'بطاقة الاختبارات والتقييمات',
        subtitle: 'رصد نتائج الاختبارات وسجلات الدرجات للطلاب',
        icon: Icons.emoji_events_rounded,
        iconColor: const Color(0xFFF59E0B),
        category: 'kpis',
        isEnabled: false,
      ),

      // 9. مؤشر وشريط إنجاز التحصيل المالي
      DashboardWidgetDef(
        id: 'financial_progress_bar',
        title: 'مؤشر وشريط إنجاز التحصيل المالي',
        subtitle: 'شريط بصري بنسبة التحصيل وتفصيل النقد والإلكتروني والمتبقي',
        icon: Icons.track_changes_rounded,
        iconColor: const Color(0xFFE11D48),
        category: 'finances',
        isEnabled: true,
      ),

      DashboardWidgetDef(
        id: 'whatsapp_quick_center',
        title: 'مركز إرسال واتساب سريع',
        subtitle: 'وصول مباشر إلى مركز رسائل واتساب',
        icon: Icons.chat_rounded,
        iconColor: const Color(0xFF25D366),
        category: 'tools',
        isEnabled: true,
      ),

      // 10. جدول ومجموعات اليوم وحصصها
      DashboardWidgetDef(
        id: 'today_groups_schedule',
        title: 'جدول ومجموعات اليوم وحصصها',
        subtitle: 'الحصص المجدولة لليوم، مواعيدها، ومقارها مع أزرار التحضير والتنبيه',
        icon: Icons.today_rounded,
        iconColor: const Color(0xFFEF4444),
        category: 'schedules',
        isEnabled: true,
      ),

      // 12. أحدث إيصالات القبض والعمليات المالية
      DashboardWidgetDef(
        id: 'recent_receipts_table',
        title: 'أحدث إيصالات القبض والعمليات المالية',
        subtitle: 'جدول تفصيلي بآخر سندات القبض مع إمكانية المعاينة والطباعة',
        icon: Icons.receipt_long_rounded,
        iconColor: const Color(0xFF475569),
        category: 'finances',
        isEnabled: true,
      ),

      // 13. جدول مواعيد المجموعات
      DashboardWidgetDef(
        id: 'all_groups_schedule_table',
        title: 'جدول مواعيد المجموعات',
        subtitle: 'مواعيد المجموعات مرتبة حسب أيام الأسبوع وأوقاتها المحددة',
        icon: Icons.calendar_view_week_rounded,
        iconColor: const Color(0xFFDC2626),
        category: 'schedules',
        isEnabled: true,
      ),

      // 14. منصة الإجراءات السريعة
      DashboardWidgetDef(
        id: 'fast_actions_platform',
        title: 'منصة الإجراءات السريعة',
        subtitle: 'أزرار سريعة للتحضير، التحصيل، إضافة طالب، وإرسال الرسائل',
        icon: Icons.bolt_rounded,
        iconColor: const Color(0xFFFBBF24),
        category: 'tools',
        isEnabled: true,
      ),

      // 15. مفكرة الملاحظات السريعة للمعلم
      DashboardWidgetDef(
        id: 'quick_notes_notepad',
        title: 'مفكرة الملاحظات السريعة للمعلم',
        subtitle: 'مساحة لتدوين الملاحظات اليومية والتذكيرات السريعة',
        icon: Icons.edit_note_rounded,
        iconColor: const Color(0xFF64748B),
        category: 'tools',
        isEnabled: false,
      ),

      // 16. قائمة المهام اليومية
      DashboardWidgetDef(
        id: 'daily_todo_list',
        title: 'قائمة المهام اليومية',
        subtitle: 'تدوين ومتابعة مهام اليوم الأكاديمية والشطب عليها بضغطة زر مع حفظ تلقائي',
        icon: Icons.check_box_rounded,
        iconColor: const Color(0xFF10B981),
        category: 'tools',
        isEnabled: false,
      ),

      // 17. مقارنة الأداء المالي والأرباح الشهرية
      DashboardWidgetDef(
        id: 'monthly_performance_comparison',
        title: 'مقارنة الأداء المالي والأرباح الشهرية',
        subtitle: 'مقارنة بصرية بين الإيرادات والمصروفات وصافي الربح لهذا الشهر مقارنة بالشهر السابق',
        icon: Icons.show_chart_rounded,
        iconColor: const Color(0xFFEF4444),
        category: 'finances',
        isEnabled: false,
      ),

      // 18. مؤشر انضباط الحضور والغياب المتكرر
      DashboardWidgetDef(
        id: 'attendance_discipline_tracker',
        title: 'مؤشر انضباط الحضور والغياب المتكرر',
        subtitle: 'رصد فوري لنسبة انضباط الطلاب وحصر الطلاب الأكثر تغيباً لسرعة التواصل',
        icon: Icons.pie_chart_outline_rounded,
        iconColor: const Color(0xFFF97316),
        category: 'kpis',
        isEnabled: false,
      ),

      // 19. حاسبة ومؤشرات الحصص الأسبوعية
      DashboardWidgetDef(
        id: 'weekly_classes_calculator',
        title: 'حاسبة ومؤشرات الحصص الأسبوعية',
        subtitle: 'شريط حي لعدد الحصص المنفذة هذا الأسبوع والمتبقية والطلاب المستهدفين',
        icon: Icons.electric_bolt_rounded,
        iconColor: const Color(0xFFF59E0B),
        category: 'schedules',
        isEnabled: false,
      ),

      // 20. متابعة إنجاز المناهج الدراسية
      DashboardWidgetDef(
        id: 'curriculum_progress_tracker',
        title: 'متابعة إنجاز المناهج الدراسية',
        subtitle: 'شريط تقدم شرح المنهج، والوحدات المكتملة والمتبقية لكل صف',
        icon: Icons.auto_stories_rounded,
        iconColor: const Color(0xFFEA580C),
        category: 'overview',
        isEnabled: true,
      ),
    ];
  }

  // --------------------------------------------------------------------------
  // Persistence Helpers
  // --------------------------------------------------------------------------

  /// Loads navigation items
  static Future<List<NavItemDef>> loadNavItems(DatabaseService database) async {
    final rawJson = await database.getSetting(keyBottomNavItems, defaultValue: '');
    final masterList = getMasterNavItems();
    if (rawJson.isEmpty) return masterList;

    try {
      final List<dynamic> decoded = jsonDecode(rawJson) as List<dynamic>;
      final Map<String, bool> enabledMap = {};
      final List<String> order = [];

      for (final item in decoded) {
        if (item is Map) {
          final id = item['id']?.toString() ?? '';
          final isEnabled = item['isEnabled'] == true;
          if (id.isNotEmpty) {
            order.add(id);
            enabledMap[id] = isEnabled;
          }
        }
      }

      // Ensure 'settings' and 'menu' are enabled so the user always has clear access
      if (enabledMap['settings'] != true) {
        enabledMap['settings'] = true;
        if (!order.contains('settings')) {
          order.insert(order.length > 1 ? 1 : order.length, 'settings');
        }
      }
      if (!enabledMap.containsKey('menu') || enabledMap['menu'] != true) {
        enabledMap['menu'] = true;
        if (!order.contains('menu')) {
          order.add('menu');
        }
      }

      final Map<String, NavItemDef> masterMap = {for (final m in masterList) m.id: m};
      final List<NavItemDef> result = [];

      for (final id in order) {
        if (masterMap.containsKey(id)) {
          final def = masterMap.remove(id)!;
          def.isEnabled = enabledMap[id] ?? def.isEnabled;
          result.add(def);
        }
      }

      for (final def in masterMap.values) {
        result.add(def);
      }

      return result;
    } catch (_) {
      return masterList;
    }
  }

  /// Saves user navigation items
  static Future<void> saveNavItems(DatabaseService database, List<NavItemDef> items) async {
    final encoded = jsonEncode(items.map((i) => i.toMap()).toList());
    await database.setSetting(keyBottomNavItems, encoded);
  }

  /// Loads Header Action Shortcuts
  static Future<List<HeaderActionDef>> loadHeaderActions(DatabaseService database) async {
    final rawJson = await database.getSetting(keyHeaderActions, defaultValue: '');
    final masterList = getMasterHeaderActions();
    if (rawJson.isEmpty) return masterList;

    try {
      final List<dynamic> decoded = jsonDecode(rawJson) as List<dynamic>;
      final Map<String, bool> enabledMap = {};
      final List<String> order = [];

      for (final item in decoded) {
        if (item is Map) {
          final id = item['id']?.toString() ?? '';
          final isEnabled = item['isEnabled'] == true;
          if (id.isNotEmpty) {
            order.add(id);
            enabledMap[id] = isEnabled;
          }
        }
      }

      final Map<String, HeaderActionDef> masterMap = {for (final m in masterList) m.id: m};
      final List<HeaderActionDef> result = [];

      for (final id in order) {
        if (masterMap.containsKey(id)) {
          final def = masterMap.remove(id)!;
          def.isEnabled = enabledMap[id] ?? def.isEnabled;
          result.add(def);
        }
      }

      for (final def in masterMap.values) {
        result.add(def);
      }

      return result;
    } catch (_) {
      return masterList;
    }
  }

  /// Saves Header Action Shortcuts
  static Future<void> saveHeaderActions(DatabaseService database, List<HeaderActionDef> actions) async {
    final encoded = jsonEncode(actions.map((a) => a.toMap()).toList());
    await database.setSetting(keyHeaderActions, encoded);
  }

  /// Loads dashboard widgets customized by user
  static Future<List<DashboardWidgetDef>> loadDashboardWidgets(DatabaseService database) async {
    final rawJson = await database.getSetting(keyDashboardWidgets, defaultValue: '');
    final masterList = getMasterDashboardWidgets();
    if (rawJson.isEmpty) return masterList;

    try {
      final List<dynamic> decoded = jsonDecode(rawJson) as List<dynamic>;
      final Map<String, bool> enabledMap = {};
      final Map<String, String> sizeMap = {};
      final List<String> order = [];

      for (final item in decoded) {
        if (item is Map) {
          final id = item['id']?.toString() ?? '';
          final isEnabled = item['isEnabled'] == true;
          final size = item['size']?.toString() ?? 'full';
          if (id.isNotEmpty) {
            order.add(id);
            enabledMap[id] = isEnabled;
            sizeMap[id] = size;
          }
        }
      }

      final Map<String, DashboardWidgetDef> masterMap = {for (final m in masterList) m.id: m};
      final List<DashboardWidgetDef> result = [];

      for (final id in order) {
        if (masterMap.containsKey(id)) {
          final def = masterMap.remove(id)!;
          def.isEnabled = enabledMap[id] ?? def.isEnabled;
          def.size = sizeMap[id] ?? def.size;
          result.add(def);
        }
      }

      // Feature Bento Grid Hub right near the top if newly introduced
      if (masterMap.containsKey('bento_grid_hub')) {
        final bentoDef = masterMap.remove('bento_grid_hub')!;
        bentoDef.isEnabled = true;
        final heroIdx = result.indexWhere((r) => r.id == 'hero_launchpad' || r.id == 'hero_header');
        if (heroIdx != -1) {
          result.insert(heroIdx + 1, bentoDef);
        } else {
          result.insert(0, bentoDef);
        }
      }

      for (final def in masterMap.values) {
        result.add(def);
      }

      return result;
    } catch (_) {
      return masterList;
    }
  }

  /// Saves user dashboard widgets
  static Future<void> saveDashboardWidgets(DatabaseService database, List<DashboardWidgetDef> widgets) async {
    final encoded = jsonEncode(widgets.map((w) => w.toMap()).toList());
    await database.setSetting(keyDashboardWidgets, encoded);
  }

  /// Check whether the bottom bar is hidden
  static Future<bool> isBottomNavHidden(DatabaseService database) async {
    final val = await database.getSetting(keyBottomNavHidden, defaultValue: 'false');
    return val == 'true';
  }

  /// Set bottom bar hidden state
  static Future<void> setBottomNavHidden(DatabaseService database, bool hidden) async {
    await database.setSetting(keyBottomNavHidden, hidden ? 'true' : 'false');
  }
}
