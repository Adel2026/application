import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database/database_service.dart';

class ThemeColorOption {
  final String id;
  final String name;
  final Color lightColor;
  final Color darkColor;

  const ThemeColorOption({
    required this.id,
    required this.name,
    required this.lightColor,
    required this.darkColor,
  });
}

class ThemeController extends ChangeNotifier {
  ThemeController(this._database);

  final DatabaseService _database;

  static const List<ThemeColorOption> availableColors = [
    ThemeColorOption(
      id: 'royal_blue',
      name: 'الأزرق الملكي الأكاديمي',
      lightColor: Color(0xFF2563EB),
      darkColor: Color(0xFF60A5FA),
    ),
    ThemeColorOption(
      id: 'emerald',
      name: 'الزمردي التعليمي',
      lightColor: Color(0xFF059669),
      darkColor: Color(0xFF34D399),
    ),
    ThemeColorOption(
      id: 'cyber_dark',
      name: 'السايبر والتكنولوجيا',
      lightColor: Color(0xFF06B6D4),
      darkColor: Color(0xFF22D3EE),
    ),
    ThemeColorOption(
      id: 'purple_elegance',
      name: 'البنفسجي الإمبراطوري',
      lightColor: Color(0xFF7C3AED),
      darkColor: Color(0xFFA78BFA),
    ),
    ThemeColorOption(
      id: 'warm_gold',
      name: 'الذهبي الدافئ',
      lightColor: Color(0xFFD97706),
      darkColor: Color(0xFFFBBF24),
    ),
    ThemeColorOption(
      id: 'minimal_slate',
      name: 'الرمادي الاحترافي',
      lightColor: Color(0xFF475569),
      darkColor: Color(0xFF94A3B8),
    ),
    ThemeColorOption(
      id: 'ocean_teal',
      name: 'المحيط الفيروزي',
      lightColor: Color(0xFF0D9488),
      darkColor: Color(0xFF2DD4BF),
    ),
    ThemeColorOption(
      id: 'ruby_red',
      name: 'الياقوتي الفاخر',
      lightColor: Color(0xFFE11D48),
      darkColor: Color(0xFFFB7185),
    ),
    ThemeColorOption(
      id: 'sunset_orange',
      name: 'غروب الشمس البرتقالي',
      lightColor: Color(0xFFEA580C),
      darkColor: Color(0xFFFB923C),
    ),
    ThemeColorOption(
      id: 'royal_indigo',
      name: 'النيلي الملكي',
      lightColor: Color(0xFF4F46E5),
      darkColor: Color(0xFF818CF8),
    ),
    ThemeColorOption(
      id: 'rose_pink',
      name: 'الوردي الراقي',
      lightColor: Color(0xFFDB2777),
      darkColor: Color(0xFFF472B6),
    ),
    ThemeColorOption(
      id: 'sky_blue',
      name: 'الأزرق السماوي',
      lightColor: Color(0xFF0284C7),
      darkColor: Color(0xFF38BDF8),
    ),
  ];

  ThemeMode _themeMode = ThemeMode.system;
  int _colorIndex = 0;
  double _cardRadius = 16.0;
  double _fontScale = 1.0;
  String _iconStyle = 'outlined';
  bool _isFullScreen = false;
  Locale _locale = const Locale('ar');

  ThemeMode get themeMode => _themeMode;
  int get colorIndex => _colorIndex;
  double get cardRadius => _cardRadius;
  double get fontScale => _fontScale;
  String get iconStyle => _iconStyle;
  bool get isFullScreen => _isFullScreen;
  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  BorderRadius get cardBorderRadius => BorderRadius.circular(_cardRadius);
  RoundedRectangleBorder get cardShape => RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardRadius));

  ThemeColorOption get currentColor => availableColors[_colorIndex.clamp(0, availableColors.length - 1)];

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  static final Map<IconData, IconData> _toOutlinedMap = {
    Icons.home: Icons.home_outlined,
    Icons.home_rounded: Icons.home_outlined,
    Icons.people: Icons.people_outline,
    Icons.people_rounded: Icons.people_outline,
    Icons.people_alt: Icons.people_alt_outlined,
    Icons.people_alt_rounded: Icons.people_alt_outlined,
    Icons.person: Icons.person_outline,
    Icons.person_rounded: Icons.person_outline,
    Icons.groups: Icons.groups_outlined,
    Icons.groups_rounded: Icons.groups_outlined,
    Icons.settings: Icons.settings_outlined,
    Icons.settings_rounded: Icons.settings_outlined,
    Icons.calendar_today: Icons.calendar_today_outlined,
    Icons.calendar_today_rounded: Icons.calendar_today_outlined,
    Icons.fact_check: Icons.fact_check_outlined,
    Icons.fact_check_rounded: Icons.fact_check_outlined,
    Icons.menu_book: Icons.menu_book_outlined,
    Icons.menu_book_rounded: Icons.menu_book_outlined,
    Icons.account_balance_wallet: Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet_rounded: Icons.account_balance_wallet_outlined,
    Icons.pie_chart: Icons.pie_chart_outline,
    Icons.pie_chart_rounded: Icons.pie_chart_outline,
    Icons.chat: Icons.chat_bubble_outline,
    Icons.chat_rounded: Icons.chat_bubble_outline,
    Icons.chat_bubble: Icons.chat_bubble_outline,
    Icons.chat_bubble_rounded: Icons.chat_bubble_outline,
    Icons.notifications: Icons.notifications_none,
    Icons.notifications_rounded: Icons.notifications_none,
    Icons.star: Icons.star_outline,
    Icons.star_rounded: Icons.star_outline,
    Icons.bookmark: Icons.bookmark_outline,
    Icons.bookmark_rounded: Icons.bookmark_outline,
    Icons.folder: Icons.folder_outlined,
    Icons.folder_rounded: Icons.folder_outlined,
    Icons.dashboard: Icons.dashboard_outlined,
    Icons.dashboard_rounded: Icons.dashboard_outlined,
    Icons.storage: Icons.storage_outlined,
    Icons.storage_rounded: Icons.storage_outlined,
    Icons.palette: Icons.palette_outlined,
    Icons.palette_rounded: Icons.palette_outlined,
    Icons.phone: Icons.phone_outlined,
    Icons.phone_rounded: Icons.phone_outlined,
    Icons.email: Icons.email_outlined,
    Icons.email_rounded: Icons.email_outlined,
    Icons.edit: Icons.edit_outlined,
    Icons.edit_rounded: Icons.edit_outlined,
    Icons.delete: Icons.delete_outline,
    Icons.delete_rounded: Icons.delete_outline,
    Icons.visibility: Icons.visibility_outlined,
    Icons.visibility_rounded: Icons.visibility_outlined,
    Icons.visibility_off: Icons.visibility_off_outlined,
    Icons.visibility_off_rounded: Icons.visibility_off_outlined,
    Icons.add_circle: Icons.add_circle_outline,
    Icons.add_circle_rounded: Icons.add_circle_outline,
    Icons.check_circle: Icons.check_circle_outline,
    Icons.check_circle_rounded: Icons.check_circle_outline,
    Icons.cancel: Icons.cancel_outlined,
    Icons.cancel_rounded: Icons.cancel_outlined,
    Icons.info: Icons.info_outline,
    Icons.info_rounded: Icons.info_outline,
    Icons.help: Icons.help_outline,
    Icons.help_rounded: Icons.help_outline,
    Icons.analytics: Icons.analytics_outlined,
    Icons.analytics_rounded: Icons.analytics_outlined,
    Icons.assessment: Icons.assessment_outlined,
    Icons.assessment_rounded: Icons.assessment_outlined,
    Icons.assignment: Icons.assignment_outlined,
    Icons.assignment_rounded: Icons.assignment_outlined,
    Icons.school: Icons.school_outlined,
    Icons.school_rounded: Icons.school_outlined,
    Icons.search: Icons.search_outlined,
    Icons.search_rounded: Icons.search_outlined,
    Icons.lock: Icons.lock_outline,
    Icons.lock_rounded: Icons.lock_outline,
    Icons.timer: Icons.timer_outlined,
    Icons.timer_rounded: Icons.timer_outlined,
    Icons.receipt_long: Icons.receipt_long_outlined,
    Icons.receipt_long_rounded: Icons.receipt_long_outlined,
    Icons.tune: Icons.tune_rounded,
  };

  static final Map<IconData, IconData> _toFilledMap = {
    Icons.home_outlined: Icons.home_rounded,
    Icons.people_outline: Icons.people_rounded,
    Icons.people_alt_outlined: Icons.people_alt_rounded,
    Icons.person_outline: Icons.person_rounded,
    Icons.groups_outlined: Icons.groups_rounded,
    Icons.settings_outlined: Icons.settings_rounded,
    Icons.calendar_today_outlined: Icons.calendar_today_rounded,
    Icons.fact_check_outlined: Icons.fact_check_rounded,
    Icons.menu_book_outlined: Icons.menu_book_rounded,
    Icons.account_balance_wallet_outlined: Icons.account_balance_wallet_rounded,
    Icons.pie_chart_outline: Icons.pie_chart_rounded,
    Icons.chat_bubble_outline: Icons.chat_bubble_rounded,
    Icons.chat_outlined: Icons.chat_rounded,
    Icons.notifications_none: Icons.notifications_rounded,
    Icons.notifications_outlined: Icons.notifications_rounded,
    Icons.star_outline: Icons.star_rounded,
    Icons.bookmark_outline: Icons.bookmark_rounded,
    Icons.folder_outlined: Icons.folder_rounded,
    Icons.dashboard_outlined: Icons.dashboard_rounded,
    Icons.storage_outlined: Icons.storage_rounded,
    Icons.palette_outlined: Icons.palette_rounded,
    Icons.phone_outlined: Icons.phone_rounded,
    Icons.email_outlined: Icons.email_rounded,
    Icons.edit_outlined: Icons.edit_rounded,
    Icons.delete_outline: Icons.delete_rounded,
    Icons.visibility_outlined: Icons.visibility_rounded,
    Icons.visibility_off_outlined: Icons.visibility_off_rounded,
    Icons.add_circle_outline: Icons.add_circle_rounded,
    Icons.check_circle_outline: Icons.check_circle_rounded,
    Icons.cancel_outlined: Icons.cancel_rounded,
    Icons.info_outline: Icons.info_rounded,
    Icons.help_outline: Icons.help_rounded,
    Icons.analytics_outlined: Icons.analytics_rounded,
    Icons.assessment_outlined: Icons.assessment_rounded,
    Icons.assignment_outlined: Icons.assignment_rounded,
    Icons.school_outlined: Icons.school_rounded,
    Icons.search_outlined: Icons.search_rounded,
    Icons.lock_outline: Icons.lock_rounded,
    Icons.timer_outlined: Icons.timer_rounded,
    Icons.receipt_long_outlined: Icons.receipt_long_rounded,
  };

  IconData resolveIcon(IconData icon) {
    if (_iconStyle == 'outlined') {
      return _toOutlinedMap[icon] ?? icon;
    } else {
      return _toFilledMap[icon] ?? icon;
    }
  }

  Future<void> loadTheme() async {
    final savedMode = await _database.getSetting('theme_mode', defaultValue: 'system');
    if (savedMode == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (savedMode == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }

    final savedColor = await _database.getSetting('theme_color_index', defaultValue: '0');
    _colorIndex = (int.tryParse(savedColor) ?? 0).clamp(0, availableColors.length - 1);

    final savedRadius = await _database.getSetting('theme_card_radius', defaultValue: '16.0');
    _cardRadius = double.tryParse(savedRadius) ?? 16.0;

    final savedFont = await _database.getSetting('theme_font_scale', defaultValue: '1.0');
    _fontScale = double.tryParse(savedFont) ?? 1.0;

    _iconStyle = await _database.getSetting('theme_icon_style', defaultValue: 'outlined');

    final savedFullScreen = await _database.getSetting('theme_fullscreen', defaultValue: 'false');
    _isFullScreen = savedFullScreen == 'true';
    _applySystemBars();

    final savedLang = await _database.getSetting('app_language', defaultValue: 'ar');
    _locale = Locale(savedLang == 'en' ? 'en' : 'ar');

    notifyListeners();
  }

  Future<void> setLanguage(String langCode) async {
    _locale = Locale(langCode == 'en' ? 'en' : 'ar');
    notifyListeners();
    await _database.setSetting('app_language', _locale.languageCode);
  }

  void _applySystemBars() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  Future<void> setFullScreen(bool enabled) async {
    _isFullScreen = enabled;
    _applySystemBars();
    notifyListeners();
    await _database.setSetting('theme_fullscreen', enabled ? 'true' : 'false');
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    String val = 'system';
    if (mode == ThemeMode.dark) val = 'dark';
    if (mode == ThemeMode.light) val = 'light';
    await _database.setSetting('theme_mode', val);
  }

  Future<void> setColorIndex(int index) async {
    _colorIndex = index.clamp(0, availableColors.length - 1);
    notifyListeners();
    await _database.setSetting('theme_color_index', _colorIndex.toString());
  }

  Future<void> setCardRadius(double radius) async {
    _cardRadius = radius;
    notifyListeners();
    await _database.setSetting('theme_card_radius', radius.toString());
  }

  Future<void> setFontScale(double scale) async {
    _fontScale = scale;
    notifyListeners();
    await _database.setSetting('theme_font_scale', scale.toString());
  }

  Future<void> setIconStyle(String style) async {
    _iconStyle = style;
    notifyListeners();
    await _database.setSetting('theme_icon_style', style);
  }

  void toggleTheme() {
    if (_themeMode == ThemeMode.dark) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.dark);
    }
  }

  void notifyCustomizationChanged() {
    notifyListeners();
  }
}
