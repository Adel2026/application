import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_icon_service.dart';
import '../core/backup_service.dart';
import '../core/contact_picker_service.dart';
import '../core/curriculum_excel_service.dart';
import '../core/database/database_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/cloud_sync_service.dart';
import 'teacher_student_app_control_screen.dart';
import '../core/excel_import_service.dart';
import '../core/google_webhook_service.dart';
import '../core/security_service.dart';
import '../core/theme_controller.dart';
import '../core/ui_customization_service.dart';
import '../core/whatsapp_service.dart';
import '../models/student_model.dart';
import '../services/home_widget_service.dart';
import '../widgets/section_top_bar.dart';
import '../widgets/circular_image_cropper_dialog.dart';
import '../widgets/visual_student_report_card.dart';

class DockItemDef {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData activeIcon;
  final Color color;

  const DockItemDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.activeIcon,
    required this.color,
  });
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.database,
    this.themeController,
    this.initialTab = 0,
    this.onNavConfigChanged,
    this.onBack,
  });

  final DatabaseService database;
  final ThemeController? themeController;
  final int initialTab;
  final VoidCallback? onNavConfigChanged;
  final VoidCallback? onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  late int _selectedTab;

  // Profile controllers
  final _centerNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _titleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _bioController = TextEditingController();
  final _facebookController = TextEditingController();
  final _youtubeController = TextEditingController();

  String? _photoPath;
  String? _customAppIconPath;
  bool _isPinShortcutSupported = true;

  // WhatsApp settings
  String _waMode = 'manual'; // 'manual' or 'api'
  String _waAppPackage = 'auto'; // 'auto', 'com.whatsapp', 'com.whatsapp.w4b'
  String _waProvider =
      'custom'; // 'custom', 'ultramsg', 'evolution', 'wassenger'
  final _waEndpointController = TextEditingController();
  final _waApiKeyController = TextEditingController();
  final _waInstanceController = TextEditingController();
  final _waFooterController = TextEditingController();
  final _waReportTemplateController = TextEditingController();
  bool _waEnableFooter = true;
  int _waDelaySeconds = 5;
  bool _waAlertAbsence = true;
  bool _waAlertCheckin = true;
  bool _waAlertExamScores = true;
  bool _waAlertFinancialReceipt = true;
  bool _waAlertSessionReminder = false;
  bool _waAlertBehavior = true;
  bool _waHideApiKey = true;
  bool _isTestingWa = false;

  // Excel management states
  bool _isExcelProcessing = false;
  bool _autoCreateGroupsOnStudentImport = true;

  // Security, App Lock & Backup states
  bool _appLockEnabled = false;
  bool _biometricsEnabled = true;
  bool _requireAuthForSensitive = true;
  bool _isBiometricsSupported = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _isResetting = false;
  String _currentPin = '1234';

  // Google Apps Script Webhook & Scheduled Cloud Backup
  final TextEditingController _webhookUrlCtrl = TextEditingController();
  bool _isTestingWebhook = false;
  bool _isUploadingCloudBackup = false;
  bool _isFetchingCloudBackups = false;
  bool _isRestoringCloudBackup = false;
  bool _isWebhookConnected = false;
  String _connectedUserEmail = '';
  bool _autoCloudBackupEnabled = true;
  String _autoCloudBackupTime = '22:00';
  String _lastAutoCloudBackupDate = '';
  List<GoogleDriveWebhookFile> _cloudBackupsList = [];
  bool _showWebhookGuide = false;

  // Dashboard Widgets settings & store
  List<DashboardWidgetDef> _dashboardWidgets = [];
  int _widgetStoreTab = 0; // 0: Active & Reorder, 1: Widget Store Catalog
  String _widgetSearchQuery = '';
  String _widgetSelectedCategory = 'all';
  final _widgetSearchController = TextEditingController();

  // Dock Management Items
  static const List<DockItemDef> _allDockItems = [
    DockItemDef(
      id: 'home',
      title: 'الرئيسية',
      subtitle: 'لوحة التحكم المركزية والإحصائيات',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      color: Color(0xFF00F2FE),
    ),
    DockItemDef(
      id: 'curriculum',
      title: 'المناهج',
      subtitle: 'الوحدات وخطط الشرح والدروس',
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book_rounded,
      color: Color(0xFF38BDF8),
    ),
    DockItemDef(
      id: 'whatsapp',
      title: 'واتساب',
      subtitle: 'تنبيهات أولياء الأمور المباشرة',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      color: Color(0xFF25D366),
    ),
    DockItemDef(
      id: 'exams',
      title: 'الامتحانات',
      subtitle: 'رصد الدرجات وبنوك الأسئلة',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
      color: Color(0xFFF472B6),
    ),
    DockItemDef(
      id: 'students',
      title: 'الطلاب',
      subtitle: 'البيانات، التسكين والاشتراكات',
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      color: Color(0xFF818CF8),
    ),
    DockItemDef(
      id: 'groups',
      title: 'المجموعات',
      subtitle: 'جداول الحصص والمواعيد والقاعات',
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
      color: Color(0xFF06B6D4),
    ),
    DockItemDef(
      id: 'timetable',
      title: 'جدول الحصص',
      subtitle: 'الجدول المدرسي وجدول الدروس والسنتر',
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month_rounded,
      color: Color(0xFF38BDF8),
    ),
    DockItemDef(
      id: 'attendance',
      title: 'التحضير الفوري',
      subtitle: 'كشف الغياب والتسميع المباشر',
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check_rounded,
      color: Color(0xFF10B981),
    ),
    DockItemDef(
      id: 'finances',
      title: 'الخزينة والمالية',
      subtitle: 'المقبوضات والمصروفات والأرباح',
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF34D399),
    ),
    DockItemDef(
      id: 'reports',
      title: 'التقارير والإحصائيات',
      subtitle: 'مؤشرات الأداء السنوية والتقييم',
      icon: Icons.insights_rounded,
      activeIcon: Icons.insights_rounded,
      color: Color(0xFFA78BFA),
    ),
    DockItemDef(
      id: 'menu',
      title: 'القائمة الكاملة',
      subtitle: 'فتح مركز التطبيقات وكافة أدوات السنتر',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
      color: Color(0xFF00F2FE),
    ),
  ];

  List<String> _activeDockItemIds = ['home', 'curriculum', 'whatsapp', 'menu'];
  double _dockIconSize = 23.0;
  String _timetableDesignTheme = 'cyber';

  // Visual Student Report Card Customization
  String _reportCardDefaultMode = 'dark'; // 'dark' or 'light'
  String _reportCardDefaultFont = 'cairo'; // 'cairo', 'tajawal', 'readexPro', 'amiri'
  String _reportCardDefaultTheme = 'cyan'; // 'cyan', 'gold', 'emerald', 'purple'
  final _reportCardTitleController = TextEditingController();
  bool _reportCardShowQr = true;
  bool _reportCardShowFinance = true;
  bool _reportCardShowStamp = true;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _loadData();
  }

  @override
  void dispose() {
    _centerNameController.dispose();
    _nameController.dispose();
    _titleController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    _facebookController.dispose();
    _youtubeController.dispose();
    _waEndpointController.dispose();
    _waApiKeyController.dispose();
    _waInstanceController.dispose();
    _waFooterController.dispose();
    _waReportTemplateController.dispose();
    _widgetSearchController.dispose();
    _webhookUrlCtrl.dispose();
    _reportCardTitleController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_nameController.text.isEmpty && _centerNameController.text.isEmpty) {
      setState(() => _isLoading = true);
    }

    // 1. Profile data
    final centerName = await widget.database
      .getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
    final name = await widget.database
        .getSetting('teacher_name', defaultValue: 'أ. أحمد السيد');
    final title = await widget.database
        .getSetting('teacher_title', defaultValue: 'خبير أول ومحاضر معتمد');
    final phone = await widget.database
        .getSetting('teacher_phone', defaultValue: '01012345678');
    final email = await widget.database
        .getSetting('teacher_email', defaultValue: 'teacher@edu-academy.com');
    final bio = await widget.database.getSetting('teacher_bio',
        defaultValue:
            'خبرة أكثر من 15 عاماً في تدريس المناهج وتأهيل أوائل الجمهورية.');
    final facebook =
        await widget.database.getSetting('teacher_facebook', defaultValue: '');
    final youtube =
        await widget.database.getSetting('teacher_youtube', defaultValue: '');

    String? photo = await widget.database
        .getSetting('teacher_photo_path', defaultValue: '');
    if (photo.isEmpty) {
      photo = await widget.database
          .getSetting('custom_logo_path', defaultValue: '');
    }
    final customIcon =
        await AppIconService.getCustomAppIconPath(widget.database);
    final pinSupported = await AppIconService.isPinShortcutSupported();

    // 2. Dock data
    final savedDock =
        await widget.database.getSetting('bottom_dock_items', defaultValue: '');
    if (savedDock.isNotEmpty) {
      try {
        final decoded = List<String>.from(jsonDecode(savedDock));
        decoded.remove('profile');
        if (decoded.length >= 2) {
          _activeDockItemIds = decoded;
        }
      } catch (_) {}
    }
    final sizeStr = await widget.database
        .getSetting('bottom_dock_icon_size', defaultValue: '23');
    _dockIconSize = double.tryParse(sizeStr) ?? 23.0;
    _timetableDesignTheme = await widget.database
        .getSetting('timetable_design_theme', defaultValue: 'cyber');

    // Visual Report Card Settings
    final rcMode = await widget.database
        .getSetting('report_card_default_mode', defaultValue: 'dark');
    final rcFont = await widget.database
        .getSetting('report_card_default_font', defaultValue: 'cairo');
    final rcTheme = await widget.database
        .getSetting('report_card_default_theme', defaultValue: 'cyan');
    final rcTitle = await widget.database.getSetting(
        'report_card_default_title',
        defaultValue: 'تقرير المتابعة والنمو الأكاديمي الشامل لولي الأمر 📊');
    final rcQr = await widget.database
        .getSetting('report_card_show_qr', defaultValue: 'true');
    final rcFinance = await widget.database
        .getSetting('report_card_show_finance', defaultValue: 'true');
    final rcStamp = await widget.database
        .getSetting('report_card_show_stamp', defaultValue: 'true');

    // 3. WhatsApp Settings
    final waMode = await widget.database
        .getSetting('whatsapp_mode', defaultValue: 'manual');
    final waAppPackage = await widget.database
        .getSetting('whatsapp_app_package', defaultValue: 'auto');
    final waProvider = await widget.database
        .getSetting('whatsapp_api_provider', defaultValue: 'custom');
    final waEndpoint = await widget.database
        .getSetting('whatsapp_api_endpoint', defaultValue: '');
    final waApiKey =
        await widget.database.getSetting('whatsapp_api_key', defaultValue: '');
    final waInstance = await widget.database
        .getSetting('whatsapp_api_instance', defaultValue: '');
    final waDelayStr = await widget.database
        .getSetting('whatsapp_send_delay_seconds', defaultValue: '5');
    final waAlertAbsence = await widget.database
        .getSetting('wa_alert_absence', defaultValue: 'true');
    final waAlertCheckin = await widget.database
        .getSetting('wa_alert_checkin', defaultValue: 'true');
    final waAlertExamScores = await widget.database
        .getSetting('wa_alert_exam_scores', defaultValue: 'true');
    final waAlertReceipt = await widget.database
        .getSetting('wa_alert_financial_receipt', defaultValue: 'true');
    final waAlertReminder = await widget.database
        .getSetting('wa_alert_session_reminder', defaultValue: 'false');
    final waAlertBehavior = await widget.database
        .getSetting('wa_alert_behavior', defaultValue: 'true');
    final waFooter = await widget.database
        .getSetting('whatsapp_message_footer', defaultValue: '');
    final waEnableFooterStr = await widget.database
        .getSetting('whatsapp_enable_footer', defaultValue: 'true');
    final waReportTemplate = await widget.database
        .getSetting('whatsapp_template_session_report', defaultValue: WhatsAppService.defaultSessionReportTemplate);

    // 4. Dashboard Widgets
    final dashboardWidgets =
        await UiCustomizationService.loadDashboardWidgets(widget.database);

    // 5. Security & App Lock Settings
    final appLock = await widget.database
        .getSetting('security_app_lock_enabled', defaultValue: 'false');
    final bioEnabled = await widget.database
        .getSetting('security_biometrics_enabled', defaultValue: 'true');
    final reqAuth = await widget.database
        .getSetting('security_require_auth', defaultValue: 'true');
    final pin =
        await widget.database.getSetting('security_pin', defaultValue: '1234');
    final isBioSupported = await SecurityService.isBiometricsSupported();

    // 6. Google Apps Script Webhook & Scheduled Cloud Backup
    final webhookUrl = await widget.database
        .getSetting('google_webhook_url', defaultValue: '');
    final autoCloudEnabled = await widget.database
        .getSetting('auto_cloud_backup_enabled', defaultValue: 'true');
    final autoCloudTime = await widget.database
        .getSetting('auto_cloud_backup_time', defaultValue: '22:00');
    final lastAutoCloudDate = await widget.database
        .getSetting('last_auto_cloud_backup_date', defaultValue: '');
    final userEmail = await widget.database
        .getSetting('google_webhook_user_email', defaultValue: '');
    final isConnected =
        webhookUrl.isNotEmpty && GoogleWebhookService.isValidUrl(webhookUrl);

    if (mounted) {
      setState(() {
        _centerNameController.text = centerName;
        _nameController.text = name;
        _titleController.text = title;
        _phoneController.text = phone;
        _emailController.text = email;
        _bioController.text = bio;
        _facebookController.text = facebook;
        _youtubeController.text = youtube;

        _waMode = waMode;
        _waAppPackage = waAppPackage;
        _waProvider = waProvider;
        if (waEndpoint.endsWith('/backend/p') ||
            waEndpoint.endsWith('/backend/p/') ||
            (waEndpoint.contains('whats-pro') &&
                !waEndpoint.contains('/messages/send'))) {
          _waEndpointController.text =
              'https://whats-pro.net/backend/public/index.php/api/messages/send';
          _waProvider = 'whatspro';
        } else {
          _waEndpointController.text = waEndpoint;
        }
        _waApiKeyController.text = waApiKey;
        _waInstanceController.text = waInstance;
        _waDelaySeconds = int.tryParse(waDelayStr) ?? 5;
        _waAlertAbsence = waAlertAbsence == 'true';
        _waAlertCheckin = waAlertCheckin == 'true';
        _waAlertExamScores = waAlertExamScores == 'true';
        _waAlertFinancialReceipt = waAlertReceipt == 'true';
        _waAlertSessionReminder = waAlertReminder == 'true';
        _waAlertBehavior = waAlertBehavior == 'true';
        if (waFooter.trim().isEmpty) {
          final c = name.isNotEmpty ? name : 'سنتر التفوق التعليمي';
          final p = phone.isNotEmpty ? '\n📞 للتواصل: $phone' : '';
          _waFooterController.text = '---\n📍 $c$p';
          widget.database.setSetting(
              'whatsapp_message_footer', _waFooterController.text.trim());
        } else {
          _waFooterController.text = waFooter;
        }
        _waEnableFooter = waEnableFooterStr == 'true';
        _waReportTemplateController.text = waReportTemplate;

        _appLockEnabled = appLock == 'true';
        _biometricsEnabled = bioEnabled == 'true';
        _requireAuthForSensitive = reqAuth == 'true';
        _currentPin = pin;
        _isBiometricsSupported = isBioSupported;

        _webhookUrlCtrl.text = webhookUrl;
        _autoCloudBackupEnabled = autoCloudEnabled == 'true';
        _autoCloudBackupTime = autoCloudTime;
        _lastAutoCloudBackupDate = lastAutoCloudDate;
        _connectedUserEmail = userEmail;
        _isWebhookConnected = isConnected;

        _dashboardWidgets = dashboardWidgets;

        _reportCardDefaultMode = rcMode;
        _reportCardDefaultFont = rcFont;
        _reportCardDefaultTheme = rcTheme;
        _reportCardTitleController.text = rcTitle;
        _reportCardShowQr = rcQr == 'true';
        _reportCardShowFinance = rcFinance == 'true';
        _reportCardShowStamp = rcStamp == 'true';

        if (photo != null && photo.isNotEmpty && File(photo).existsSync()) {
          _photoPath = photo;
        } else {
          _photoPath = null;
        }
        _customAppIconPath = customIcon;
        _isPinShortcutSupported = pinSupported;

        _isLoading = false;
      });

      if (isConnected) {
        _fetchCloudBackupsList();
      }
    }
  }

  Future<void> _saveWidgetsConfig() async {
    widget.onNavConfigChanged?.call();
    await UiCustomizationService.saveDashboardWidgets(
        widget.database, _dashboardWidgets);
    widget.onNavConfigChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFF6366F1),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم حفظ إعدادات الودجات وتحديث الشاشة الرئيسية فوراً',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _restoreWidgetsDefaults() async {
    final defaults = UiCustomizationService.getMasterDashboardWidgets();
    setState(() {
      _dashboardWidgets = defaults;
    });
    await _saveWidgetsConfig();
  }

  void _changeWidgetSize(DashboardWidgetDef def, String newSize) {
    HapticFeedback.selectionClick();
    setState(() {
      def.size = newSize;
    });
    _saveWidgetsConfig();
  }

  void _toggleWidget(DashboardWidgetDef def) {
    HapticFeedback.selectionClick();
    setState(() {
      def.isEnabled = !def.isEnabled;
    });
    _saveWidgetsConfig();
  }

  Future<void> _saveDockConfig() async {
    widget.onNavConfigChanged?.call();
    await widget.database
        .setSetting('bottom_dock_items', jsonEncode(_activeDockItemIds));
    widget.onNavConfigChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFF0284C7),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم تحديث ترتيب الشريط الرئيسي فوراً',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _saveDockIconSize(double size) async {
    _dockIconSize = size;
    await widget.database
        .setSetting('bottom_dock_icon_size', size.toStringAsFixed(1));
    widget.onNavConfigChanged?.call();
  }

  Future<void> _pickPhotoFromPhone() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
      );

      if (files.isNotEmpty && files.first.path != null) {
        final pickedPath = files.first.path!;

        if (!mounted) return;
        final croppedFile = await CircularImageCropper.cropImage(
          context,
          imagePath: pickedPath,
          title: 'صورة البروفايل',
        );
        if (croppedFile == null) return;

        final appDir = await getApplicationDocumentsDirectory();
        final ext = p.extension(croppedFile.path).isEmpty
            ? '.png'
            : p.extension(croppedFile.path);
        final targetFileName =
            'teacher_avatar_${DateTime.now().millisecondsSinceEpoch}$ext';
        final savedFile =
            await croppedFile.copy(p.join(appDir.path, targetFileName));

        setState(() {
          _photoPath = savedFile.path;
        });

        await widget.database.setSetting('teacher_photo_path', savedFile.path);
        await widget.database.setSetting('custom_logo_path', savedFile.path);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF059669),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text('تم قص وضبط وحفظ صورة البروفايل بنجاح 🌟',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text('تعذر اختيار الصورة: $e',
                style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  Future<void> _removePhoto() async {
    setState(() {
      _photoPath = null;
    });
    await widget.database.setSetting('teacher_photo_path', '');
    await widget.database.setSetting('custom_logo_path', '');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF334155),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('تم حذف الصورة واستعادة الرمز الافتراضي',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _pickAndSetAppIcon() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty || result.first.path == null) {
        return;
      }

      final pickedPath = result.first.path!;
      if (!mounted) return;
      final croppedFile = await CircularImageCropper.cropImage(
        context,
        imagePath: pickedPath,
        title: 'أيقونة التطبيق',
      );
      if (croppedFile == null) return;

      final appName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'سنتر أستاذي';

      await AppIconService.setCustomAppIconAndPin(
        database: widget.database,
        sourceImagePath: croppedFile.path,
        customAppName: appName,
      );

      final updatedPath =
          await AppIconService.getCustomAppIconPath(widget.database);
      if (mounted) {
        setState(() {
          _customAppIconPath = updatedPath;
          _photoPath = updatedPath;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF059669),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم حفظ أيقونة التطبيق بنجاح وإرسال طلب التثبيت للشاشة الرئيسية 📱',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text('تعذر تعيين الأيقونة: $e',
                style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  Future<void> _rePinExistingAppIcon() async {
    if (_customAppIconPath == null || _customAppIconPath!.isEmpty) return;
    try {
      final appName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'سنتر أستاذي';

      await AppIconService.setCustomAppIconAndPin(
        database: widget.database,
        sourceImagePath: _customAppIconPath!,
        customAppName: appName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF0284C7),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Row(
              children: [
                Icon(Icons.push_pin_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text('تم إرسال طلب التثبيت للشاشة الرئيسية بنجاح 📱',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            content: Text('حدث خطأ: $e',
                style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  Future<void> _resetAppIcon() async {
    await AppIconService.resetCustomAppIcon(widget.database);
    if (mounted) {
      setState(() {
        _customAppIconPath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF334155),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Row(
            children: [
              Icon(Icons.restore_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('تم استعادة أيقونة وشعار التطبيق الافتراضي بنجاح',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _saveProfileChanges() async {
    if (_centerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسم السنتر أو الأكاديمية أولاً')),
      );
      return;
    }

    setState(() => _isSaving = true);

    await widget.database
        .setSetting('center_name', _centerNameController.text.trim());
    await widget.database
        .setSetting('teacher_name', _nameController.text.trim());
    await widget.database
        .setSetting('teacher_title', _titleController.text.trim());
    await widget.database
        .setSetting('teacher_phone', _phoneController.text.trim());
    await widget.database
        .setSetting('teacher_email', _emailController.text.trim());
    await widget.database.setSetting('teacher_bio', _bioController.text.trim());
    await widget.database
        .setSetting('teacher_facebook', _facebookController.text.trim());
    await widget.database
        .setSetting('teacher_youtube', _youtubeController.text.trim());

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF10B981),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
          content: const Row(
            children: [
              Icon(Icons.task_alt_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تم حفظ جميع بيانات الملف الشخصي بنجاح',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    String appBarTitle;
    if (_selectedTab == 0) {
      appBarTitle = 'إدارة الشريط الرئيسي';
    } else if (_selectedTab == 1) {
      appBarTitle = 'إدارة ومتجر ودجات الشاشة';
    } else if (_selectedTab == 2) {
      appBarTitle = 'إدارة وتكامل واتساب';
    } else if (_selectedTab == 3) {
      appBarTitle = 'إدارة واستيراد بيانات Excel';
    } else {
      appBarTitle = 'الحماية والنسخ الاحتياطي والأمان';
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF070E1A) : const Color(0xFFF8FAFC),
        appBar: SectionTopBar(
          title: appBarTitle,
          icon: Icons.settings_rounded,
          onBack: widget.onBack,
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: _buildSettingsBottomDock(isDark, primaryColor),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator.adaptive())
            : (_selectedTab == 0
                ? _buildDockManagementTab(isDark, primaryColor)
                : (_selectedTab == 1
                    ? _buildWidgetsManagementTab(isDark, primaryColor)
                    : (_selectedTab == 2
                        ? _buildWhatsAppSettingsTab(isDark, primaryColor)
                        : (_selectedTab == 3
                            ? _buildExcelManagementTab(isDark, primaryColor)
                            : _buildSecurityManagementTab(
                                isDark, primaryColor))))),
      ),
    );
  }

  // ==========================================================================
  // TAB 1: BOTTOM DOCK & APP ICON MANAGEMENT (إدارة الشريط والمظهر والأيقونة)
  // ==========================================================================
  Widget _buildHomeWidgetCard(bool isDark, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101B30) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.45 : 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.widgets_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'أداة سطح المكتب الحية (Widget)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'جديد 📱',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'عرض الحصة القادمة وتوقيتها وزر التحضير من شاشة الموبايل الرئيسية',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'أداة تفاعلية أنيقة توضع على شاشة الموبايل الرئيسية وتتحدث تلقائياً. تظهر اسم المجموعة، الصف الدراسي، التوقيت، وزر تحضير مباشر يفتح لك كشف الحصة بلمسة واحدة.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                  label: const Text(
                    'إضافة الأداة للشاشة الرئيسية',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await HomeWidgetService.updateNextSessionWidget(database: widget.database);
                    final success = await HomeWidgetService.pinWidgetToHomeScreen();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: success ? Colors.green : const Color(0xFF1E293B),
                        content: Text(
                          success
                              ? 'تم إرسال طلب إضافة الأداة لشاشتك الرئيسية بنجاح ✅ اضغط "إضافة" في الرسالة الظاهرة.'
                              : 'يمكنك إضافة الأداة بسهولة: اضغط مطولاً على أي مساحة فارغة في شاشة هاتفك الرئيسية، ثم اختر أدوات (Widgets) واختر "سنتر أستاذي" 📱',
                        ),
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('تحديث'),
                onPressed: () async {
                  await HomeWidgetService.updateNextSessionWidget(database: widget.database);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تحديث بيانات الأداة الآن بنجاح 🔄'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppIconCustomizerCard(bool isDark, Color primaryColor) {
    final bool hasCustomIcon = _customAppIconPath != null &&
        _customAppIconPath!.isNotEmpty &&
        File(_customAppIconPath!).existsSync();

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101B30) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF1E3255) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.app_shortcut_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'أيقونة التطبيق والشاشة الرئيسية',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14.5),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF00F2FE).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'جديد',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00F2FE)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'اختر أي صورة من هاتفك لتثبيتها كأيقونة للتطبيق على شاشة هاتفك الرئيسية',
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live Icon Preview Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0A1222) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isDark ? const Color(0xFF162544) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                // Icon representation
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE2E8F0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                    border: Border.all(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: hasCustomIcon
                        ? Image.file(
                            File(_customAppIconPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.school_rounded,
                                color: Color(0xFF00F2FE),
                                size: 36),
                          )
                        : Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.school_rounded,
                                color: Color(0xFF00F2FE),
                                size: 36),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                // Icon Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasCustomIcon
                            ? 'أيقونة مخصصة من الهاتف'
                            : 'الأيقونة والشعار الأصلي',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasCustomIcon
                            ? 'تم اعتماد الصورة كأيقونة للتطبيق وشعار رسمي للهيدر الداخلي'
                            : 'انقر على الزر بالأسفل لاختيار أي لوجو أو صورة من معرض الصور',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            hasCustomIcon
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            size: 14,
                            color: hasCustomIcon
                                ? const Color(0xFF10B981)
                                : const Color(0xFF38BDF8),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            hasCustomIcon
                                ? 'مفعّلة كأيقونة وشعار'
                                : 'الأيقونة الافتراضية',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: hasCustomIcon
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF38BDF8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    foregroundColor: const Color(0xFF041226),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 19),
                  label: Text(
                    hasCustomIcon
                        ? 'تغيير صورة الأيقونة'
                        : 'اختيار صورة وتثبيت الأيقونة',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: _pickAndSetAppIcon,
                ),
              ),
              if (hasCustomIcon) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'إعادة تثبيت الأيقونة على الشاشة الرئيسية',
                  style: IconButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF00F2FE).withValues(alpha: 0.15),
                    foregroundColor: const Color(0xFF00F2FE),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.push_pin_rounded, size: 20),
                  onPressed: _rePinExistingAppIcon,
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'استعادة الأيقونة الافتراضية',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.12),
                    foregroundColor: const Color(0xFFEF4444),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.restore_rounded, size: 20),
                  onPressed: _resetAppIcon,
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),
          // Tip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _isPinShortcutSupported
                        ? 'سيطلب منك الهاتف تأكيد إضافة الأيقونة إلى الشاشة الرئيسية، وافق عليها ليظهر التطبيق بالصورة الجديدة مباشرة.'
                        : 'تنبيه: واجهة المشغل في هذا الهاتف قد لا تتيح تثبيت الاختصارات تلقائياً، ولكن سيتم تحديث أيقونة وشعار التطبيق الداخلي بنجاح.',
                    style: TextStyle(
                      fontSize: 10,
                      color:
                          isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockManagementTab(bool isDark, Color primaryColor) {
    final activeDefs = _activeDockItemIds
        .map((id) => _allDockItems.firstWhere((item) => item.id == id,
            orElse: () => _allDockItems.first))
        .toList();

    final availableDefs = _allDockItems
        .where((item) => !_activeDockItemIds.contains(item.id))
        .toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Home Screen Widget Card
          _buildHomeWidgetCard(isDark, primaryColor),
          // App Icon Customizer
          _buildAppIconCustomizerCard(isDark, primaryColor),
          _buildTimetableDesignThemeCard(isDark, primaryColor),
          // Visual Student Report Card Settings Card
          _buildVisualReportCardSettingsCard(isDark, primaryColor),

          // Banner explanation
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF132247), Color(0xFF0F1A30)])
                  : const LinearGradient(
                      colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isDark ? const Color(0x4D38BDF8) : const Color(0xFFBFDBFE),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.touch_app_rounded,
                      color: Color(0xFF00F2FE), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تخصيص أيقونات الشريط السفلي',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'اسحب الأيقونات لإعادة ترتيبها بالسحب والإفلات، أو أضف واحذف التبويبات حسب رغبتك اليومية.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Live Preview Header
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00F2FE),
                  boxShadow: [
                    BoxShadow(color: Color(0xFF00F2FE), blurRadius: 4)
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'معاينة حية للشريط السفلي (تتحدث فوراً)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Live Preview Capsule Bar
          _buildLiveDockPreview(isDark, activeDefs),
          const SizedBox(height: 18),

          // Icon Size Control Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF101B30) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isDark ? const Color(0xFF1E3255) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.photo_size_select_actual_outlined,
                        color: Color(0xFF00F2FE), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'حجم أيقونات الشريط السفلي',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_dockIconSize.round()} px',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF00F2FE)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildIconSizeChoice('صغير', 18.0, isDark),
                    const SizedBox(width: 8),
                    _buildIconSizeChoice('عادي', 22.0, isDark),
                    const SizedBox(width: 8),
                    _buildIconSizeChoice('متوسط', 26.0, isDark),
                    const SizedBox(width: 8),
                    _buildIconSizeChoice('كبير', 30.0, isDark),
                  ],
                ),
                const SizedBox(height: 10),
                Slider(
                  value: _dockIconSize.clamp(16.0, 34.0),
                  min: 16.0,
                  max: 34.0,
                  divisions: 9,
                  activeColor: const Color(0xFF00F2FE),
                  inactiveColor: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFCBD5E1),
                  onChanged: (val) {
                    setState(() {
                      _dockIconSize = val;
                    });
                    _saveDockIconSize(val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 1: Active Tabs with Drag & Drop
          Row(
            children: [
              const Icon(Icons.reorder_rounded,
                  color: Color(0xFF00F2FE), size: 20),
              const SizedBox(width: 8),
              const Text(
                'التبويبات النشطة (اسحب للترتيب)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Text(
                '${_activeDockItemIds.length} من أصل ${_allDockItems.length} تبويب مفعل',
                style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white60 : Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Reorderable list
          Theme(
            data: Theme.of(context).copyWith(
              canvasColor: Colors.transparent,
              shadowColor: Colors.transparent,
            ),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeDefs.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = _activeDockItemIds.removeAt(oldIndex);
                  _activeDockItemIds.insert(newIndex, item);
                });
                _saveDockConfig();
              },
              itemBuilder: (context, index) {
                final item = activeDefs[index];
                return Container(
                  key: ValueKey('active_${item.id}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF101B30) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF1E3255)
                          : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Drag handle icon
                      const Icon(Icons.drag_indicator_rounded,
                          color: Colors.grey, size: 22),
                      const SizedBox(width: 10),
                      // Icon badge
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item.icon, color: item.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      // Remove button
                      if (_activeDockItemIds.length > 2)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded,
                              color: Color(0xFFF43F5E), size: 22),
                          tooltip: 'إزالة من الشريط',
                          onPressed: () {
                            setState(() {
                              _activeDockItemIds.remove(item.id);
                            });
                            _saveDockConfig();
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),

          // Section 2: Available Tabs to Add
          if (availableDefs.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.add_to_photos_rounded,
                    color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'أقسام متاحة للإضافة إلى الشريط',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: availableDefs.length,
              itemBuilder: (context, index) {
                final item = availableDefs[index];
                final bool canAdd =
                    _activeDockItemIds.length < _allDockItems.length;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0C1527)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF1A2A47)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item.icon, color: item.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: canAdd
                              ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.1),
                          foregroundColor:
                              canAdd ? const Color(0xFF00F2FE) : Colors.grey,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('إضافة',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: canAdd
                            ? () {
                                setState(() {
                                  _activeDockItemIds.add(item.id);
                                });
                                _saveDockConfig();
                              }
                            : null,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimetableDesignThemeCard(bool isDark, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101B2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.style_rounded,
                    color: Color(0xFF00F2FE), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'نمط تصميم جدول الحصص والدروس 📅',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'اختر الشكل المفضل ويمكنك التبديل بينهما في أي وقت من هنا أو من شاشة الجدول:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Option 1: Cyber Neon Bento
              Expanded(
                child: InkWell(
                  onTap: () async {
                    setState(() => _timetableDesignTheme = 'cyber');
                    await widget.database
                        .setSetting('timetable_design_theme', 'cyber');
                    widget.onNavConfigChanged?.call();
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _timetableDesignTheme == 'cyber'
                          ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                          : (isDark
                              ? const Color(0xFF141E33)
                              : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _timetableDesignTheme == 'cyber'
                            ? const Color(0xFF00F2FE)
                            : (isDark
                                ? const Color(0xFF223147)
                                : const Color(0xFFCBD5E1)),
                        width: _timetableDesignTheme == 'cyber' ? 1.8 : 1.0,
                      ),
                      boxShadow: _timetableDesignTheme == 'cyber'
                          ? [
                              BoxShadow(
                                color: const Color(0xFF00F2FE)
                                    .withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.auto_awesome_rounded,
                            color: Color(0xFF00F2FE), size: 24),
                        const SizedBox(height: 6),
                        const Text(
                          'نيون عصري Bento',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'أرقام ضخمة 01/02 وشريط الفصول',
                          style: TextStyle(
                              fontSize: 9.5,
                              color: isDark ? Colors.grey : Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Option 2: Classic Grid
              Expanded(
                child: InkWell(
                  onTap: () async {
                    setState(() => _timetableDesignTheme = 'classic');
                    await widget.database
                        .setSetting('timetable_design_theme', 'classic');
                    widget.onNavConfigChanged?.call();
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _timetableDesignTheme == 'classic'
                          ? const Color(0xFF2563EB).withValues(alpha: 0.15)
                          : (isDark
                              ? const Color(0xFF141E33)
                              : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _timetableDesignTheme == 'classic'
                            ? const Color(0xFF38BDF8)
                            : (isDark
                                ? const Color(0xFF223147)
                                : const Color(0xFFCBD5E1)),
                        width: _timetableDesignTheme == 'classic' ? 1.8 : 1.0,
                      ),
                      boxShadow: _timetableDesignTheme == 'classic'
                          ? [
                              BoxShadow(
                                color: const Color(0xFF2563EB)
                                    .withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.grid_on_rounded,
                            color: Color(0xFF38BDF8), size: 24),
                        const SizedBox(height: 6),
                        const Text(
                          'جدول شبكي كامل',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'مصفوفة أسبوعية مقسمة بالحصة',
                          style: TextStyle(
                              fontSize: 9.5,
                              color: isDark ? Colors.grey : Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisualReportCardSettingsCard(bool isDark, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101B2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title & Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00F2FE), Color(0xFF0284C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.badge_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'كارت تقرير الطالب المصور الرقمي 📊✨',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'تخصيص المظهر الافتراضي، الوضع النهاري والليلي، والبيانات المعتمدة:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. Day / Night Mode Bento Cards
          Text(
            'خلفية الكارت الافتراضية (نهاري / ليلي):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Night Mode Bento
              Expanded(
                child: InkWell(
                  onTap: () async {
                    setState(() => _reportCardDefaultMode = 'dark');
                    await widget.database.setSetting('report_card_default_mode', 'dark');
                    HapticFeedback.selectionClick();
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _reportCardDefaultMode == 'dark'
                          ? const Color(0xFF0F172A)
                          : (isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _reportCardDefaultMode == 'dark'
                            ? const Color(0xFF00F2FE)
                            : (isDark ? const Color(0xFF223147) : const Color(0xFFCBD5E1)),
                        width: _reportCardDefaultMode == 'dark' ? 1.8 : 1.0,
                      ),
                      boxShadow: _reportCardDefaultMode == 'dark'
                          ? [
                              BoxShadow(
                                color: const Color(0xFF00F2FE).withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('🌙', style: TextStyle(fontSize: 18)),
                            SizedBox(width: 6),
                            Text(
                              'ليلي فاخر',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'كحلي ملكي داكن مع تباين نيون فائق',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark ? Colors.grey : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Day Mode Bento
              Expanded(
                child: InkWell(
                  onTap: () async {
                    setState(() => _reportCardDefaultMode = 'light');
                    await widget.database.setSetting('report_card_default_mode', 'light');
                    HapticFeedback.selectionClick();
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _reportCardDefaultMode == 'light'
                          ? const Color(0xFFFFFBEB)
                          : (isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _reportCardDefaultMode == 'light'
                            ? const Color(0xFFF59E0B)
                            : (isDark ? const Color(0xFF223147) : const Color(0xFFCBD5E1)),
                        width: _reportCardDefaultMode == 'light' ? 1.8 : 1.0,
                      ),
                      boxShadow: _reportCardDefaultMode == 'light'
                          ? [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('☀️', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 6),
                            Text(
                              'نهاري عاجي',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _reportCardDefaultMode == 'light'
                                    ? const Color(0xFF92400E)
                                    : (isDark ? Colors.white70 : const Color(0xFF0F172A)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'أبيض ناصع عاجي مريح ومناسب للطباعة',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark ? Colors.grey : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2. Default Font Chips
          Text(
            'نوع الخط العربي المعتمد:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ReportCardFont.values.map((f) {
                final isSel = _reportCardDefaultFont == f.name;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(
                      f.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSel,
                    selectedColor: const Color(0xFF00F2FE),
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    labelStyle: TextStyle(
                      color: isSel ? Colors.black : (isDark ? Colors.white70 : const Color(0xFF334155)),
                    ),
                    onSelected: (val) async {
                      if (val) {
                        setState(() => _reportCardDefaultFont = f.name);
                        await widget.database.setSetting('report_card_default_font', f.name);
                        HapticFeedback.selectionClick();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // 3. Theme Palette Chips
          Text(
            'النمط اللوني المفضل:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ReportCardTheme.values.map((t) {
                final isSel = _reportCardDefaultTheme == t.name;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(
                      t.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSel,
                    selectedColor: t.primary,
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    labelStyle: TextStyle(
                      color: isSel ? Colors.black : (isDark ? Colors.white70 : const Color(0xFF334155)),
                    ),
                    onSelected: (val) async {
                      if (val) {
                        setState(() => _reportCardDefaultTheme = t.name);
                        await widget.database.setSetting('report_card_default_theme', t.name);
                        HapticFeedback.selectionClick();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // 4. Default Report Title TextField
          Text(
            'عنوان التقرير الافتراضي أعلى الكارت:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _reportCardTitleController,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'تقرير المتابعة والنمو الأكاديمي الشامل لولي الأمر 📊',
              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              filled: true,
              fillColor: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? const Color(0xFF223147) : const Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? const Color(0xFF223147) : const Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF00F2FE)),
              ),
            ),
            onChanged: (val) async {
              await widget.database.setSetting('report_card_default_title', val.trim());
            },
          ),
          const SizedBox(height: 14),

          // 5. Switches for approved elements
          Text(
            'العناصر المعتمدة داخل الكارت:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          _buildReportCardSwitchRow(
            title: 'إظهار باركود التوثيق المعتمد (QR Code)',
            subtitle: 'رمز QR للتحقق السريع ومسح التقرير إلكترونياً',
            icon: Icons.qr_code_2_rounded,
            value: _reportCardShowQr,
            isDark: isDark,
            onChanged: (val) async {
              setState(() => _reportCardShowQr = val);
              await widget.database.setSetting('report_card_show_qr', val.toString());
            },
          ),
          const SizedBox(height: 4),
          _buildReportCardSwitchRow(
            title: 'إظهار الموقف المالي للطالب',
            subtitle: 'عرض بطاقة الرصيد المطلوب أو مسدد بالكامل',
            icon: Icons.account_balance_wallet_rounded,
            value: _reportCardShowFinance,
            isDark: isDark,
            onChanged: (val) async {
              setState(() => _reportCardShowFinance = val);
              await widget.database.setSetting('report_card_show_finance', val.toString());
            },
          ),
          const SizedBox(height: 4),
          _buildReportCardSwitchRow(
            title: 'إظهار ختم الإدارة وتوقيع المعلم',
            subtitle: 'عرض الختم الإداري الدائري وخط توقيع أستاذ المادة',
            icon: Icons.verified_rounded,
            value: _reportCardShowStamp,
            isDark: isDark,
            onChanged: (val) async {
              setState(() => _reportCardShowStamp = val);
              await widget.database.setSetting('report_card_show_stamp', val.toString());
            },
          ),
          const SizedBox(height: 14),

          // 6. Live Interactive Preview Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00F2FE),
                side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.remove_red_eye_rounded, size: 18),
              label: const Text(
                'معاينة شكل كارت التقرير الآن 👁️✨',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () {
                const sampleStudent = StudentModel(
                  id: 'STD-1001',
                  fullName: 'محمد أحمد محمود',
                  stage: 'المرحلة الثانوية',
                  grade: 'الصف الثالث الثانوي',
                  studentPhone: '01012345678',
                  parentPhone: '01123456789',
                  groupId: 'GRP-A',
                  paymentPlan: 'monthly',
                  outstandingAmount: 0,
                );

                VisualReportCardModalSheet.show(
                  context,
                  student: sampleStudent,
                  groupName: 'مجموعة النخبة والأوائل',
                  attendancePercent: 100,
                  presentCount: 8,
                  totalSessions: 8,
                  averageScorePercent: 96.5,
                  examScores: const [
                    {'title': 'امتحان شامل - الوحدة الأولى', 'score': 49, 'max_score': 50, 'date': '2026-11-15'},
                    {'title': 'كويز المفاهيم الأساسية', 'score': 20, 'max_score': 20, 'date': '2026-11-10'},
                    {'title': 'تطبيق أسبوعي مكثف', 'score': 28, 'max_score': 30, 'date': '2026-11-05'},
                  ],
                  teacherNote: 'أداء مبهر واستيعاب نموذجي لجميع الأفكار المتقدمة. استمر في التميز 🌟',
                  centerName: _centerNameController.text.trim().isNotEmpty
                      ? _centerNameController.text.trim()
                      : 'أكاديمية التفوق التعليمية',
                  teacherName: _nameController.text.trim().isNotEmpty
                      ? _nameController.text.trim()
                      : 'أستاذ المادة',
                  rankText: 'المركز الأول على المجموعة 🥇',
                  reportTitle: _reportCardTitleController.text.trim().isNotEmpty
                      ? _reportCardTitleController.text.trim()
                      : 'تقرير المتابعة والنمو الأكاديمي الشامل لولي الأمر 📊',
                  database: widget.database,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCardSwitchRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required bool isDark,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141E33).withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00F2FE), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 9.5, color: Colors.grey),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF00F2FE),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildIconSizeChoice(String title, double size, bool isDark) {
    final bool isSelected = (_dockIconSize - size).abs() < 1.5;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _dockIconSize = size;
          });
          _saveDockIconSize(size);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00F2FE).withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF00F2FE)
                  : (isDark
                      ? const Color(0xFF1E3255)
                      : const Color(0xFFCBD5E1)),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? const Color(0xFF00F2FE)
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${size.round()}px',
                style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? const Color(0xFF00F2FE) : Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Live Dock Preview Widget ---
  Widget _buildLiveDockPreview(bool isDark, List<DockItemDef> activeDefs) {
    final double previewHeight =
        (52.0 + (_dockIconSize - 22.0) * 0.7).clamp(50.0, 68.0);
    return Container(
      height: previewHeight,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF2091222) : Colors.white,
        borderRadius: BorderRadius.circular(previewHeight / 2),
        border: Border.all(
          color: isDark ? const Color(0x3338BDF8) : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(previewHeight / 2),
        child: Row(
          children: [
            for (int i = 0; i < activeDefs.length; i++)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Icon(
                        activeDefs[i].icon,
                        size: _dockIconSize,
                        color: i == 0 ? const Color(0xFF00F2FE) : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (i == 0)
                      Container(
                        width: 18,
                        height: 2.2,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F2FE),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- Sleek Slim Bottom Dock for Settings Tabs (5 Tabs) ---
  Widget _buildSettingsBottomDock(bool isDark, Color primaryColor) {
    // 5 tabs in RTL:
    // Tab 0 (الشريط): targetX = 1.0
    // Tab 1 (الودجات): targetX = 0.5
    // Tab 2 (واتساب): targetX = 0.0
    // Tab 3 (Excel): targetX = -0.5
    // Tab 4 (الحماية): targetX = -1.0
    final double targetX = 1.0 - _selectedTab * 0.50;
    Color activeIndicatorColor;
    if (_selectedTab == 0) {
      activeIndicatorColor = const Color(0xFF00F2FE);
    } else if (_selectedTab == 1) {
      activeIndicatorColor = const Color(0xFF818CF8);
    } else if (_selectedTab == 2) {
      activeIndicatorColor = const Color(0xFF25D366);
    } else if (_selectedTab == 3) {
      activeIndicatorColor = const Color(0xFF10B981);
    } else {
      activeIndicatorColor = const Color(0xFFF59E0B);
    }

    return Container(
      key: const ValueKey('settings_capsule_dock'),
      height: 52,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xF2091222)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark ? const Color(0x3338BDF8) : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          if (isDark)
            BoxShadow(
              color: activeIndicatorColor.withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            // 1. Sliding indicator line (at bottom edge)
            AnimatedAlign(
              alignment: Alignment(targetX, 0.90),
              duration: const Duration(milliseconds: 200),
              curve: Curves.fastEaseInToSlowEaseOut,
              child: Container(
                width: 28,
                height: 2.8,
                decoration: BoxDecoration(
                  color: activeIndicatorColor,
                  borderRadius: BorderRadius.circular(1.5),
                  boxShadow: [
                    BoxShadow(
                      color: activeIndicatorColor,
                      blurRadius: 6,
                      spreadRadius: 0.6,
                    ),
                  ],
                ),
              ),
            ),

            // 2. Sliding radial glow halo
            AnimatedAlign(
              alignment: Alignment(targetX, 0.0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.fastEaseInToSlowEaseOut,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: activeIndicatorColor.withValues(alpha: 0.22),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),

            // 3. Row of 4 tabs
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSettingsDockTab(
                  index: 0,
                  label: 'المظهر والأيقونة',
                  icon: Icons.tune_rounded,
                  activeColor: const Color(0xFF00F2FE),
                  isDark: isDark,
                ),
                _buildSettingsDockTab(
                  index: 1,
                  label: 'الودجات',
                  icon: Icons.dashboard_customize_rounded,
                  activeColor: const Color(0xFF818CF8),
                  isDark: isDark,
                ),
                _buildSettingsDockTab(
                  index: 2,
                  label: 'واتساب',
                  icon: Icons.chat_bubble_rounded,
                  activeColor: const Color(0xFF25D366),
                  isDark: isDark,
                ),
                _buildSettingsDockTab(
                  index: 3,
                  label: 'Excel',
                  icon: Icons.table_chart_rounded,
                  activeColor: const Color(0xFF10B981),
                  isDark: isDark,
                ),
                _buildSettingsDockTab(
                  index: 4,
                  label: 'الحماية',
                  icon: Icons.shield_rounded,
                  activeColor: const Color(0xFFF59E0B),
                  isDark: isDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsDockTab({
    required int index,
    required String label,
    required IconData icon,
    required Color activeColor,
    required bool isDark,
  }) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (_selectedTab != index) {
            HapticFeedback.selectionClick();
            setState(() => _selectedTab = index);
          }
        },
        borderRadius: BorderRadius.circular(26),
        splashColor: activeColor.withValues(alpha: 0.2),
        highlightColor: Colors.transparent,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14.5,
                color: isSelected
                    ? activeColor
                    : (isDark
                        ? const Color(0xFF8E9BAE)
                        : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? activeColor
                        : (isDark
                            ? const Color(0xFF8E9BAE)
                            : const Color(0xFF64748B)),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // TAB 2: DASHBOARD WIDGETS MANAGEMENT & STORE (إدارة ومتجر ودجات الشاشة)
  // ==========================================================================
  Widget _buildWidgetsManagementTab(bool isDark, Color primaryColor) {
    final activeWidgets = _dashboardWidgets.where((w) => w.isEnabled).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Hero Banner
          _buildWidgetsHeroBanner(isDark),
          const SizedBox(height: 18),

          // 2. Segmented Sub-view Switcher (Active Widgets vs Store)
          _buildWidgetsSubTabSelector(
              isDark, activeWidgets.length, _dashboardWidgets.length),
          const SizedBox(height: 18),

          // 3. Tab Content
          if (_widgetStoreTab == 0)
            _buildActiveWidgetsReorderSection(isDark, activeWidgets)
          else
            _buildWidgetStoreCatalogSection(isDark),

          const SizedBox(height: 24),

          // 4. Save & Refresh Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: const Color(0x666366F1),
              ),
              onPressed: _saveWidgetsConfig,
              icon: const Icon(Icons.check_circle_rounded, size: 22),
              label: const Text(
                'حفظ وتحديث الشاشة الرئيسية فوراً',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetsHeroBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFEEF2FF), Color(0xFFF8FAFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.35 : 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF6366F1).withValues(alpha: isDark ? 0.16 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF818CF8), Color(0xFF4F46E5)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.dashboard_customize_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إدارة ومتجر ودجات الشاشة الرئيسية',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                SizedBox(height: 3),
                Text(
                  'تحكم كامل في ترتيب الودجات بالسحب والإفلات، ضبط المقاسات (كامل، نصفين، مدمج)، واستكشاف المتجر لإضافة بطاقات جديدة.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetsSubTabSelector(
      bool isDark, int activeCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSubTabButton(
              index: 0,
              label: 'الودجات المفعلة على الشاشة ($activeCount)',
              icon: Icons.view_quilt_rounded,
              isDark: isDark,
            ),
          ),
          Expanded(
            child: _buildSubTabButton(
              index: 1,
              label: 'متجر الودجات ($totalCount)',
              icon: Icons.storefront_rounded,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabButton({
    required int index,
    required String label,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _widgetStoreTab == index;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _widgetStoreTab = index);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF1E293B) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                  width: 1.2,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? const Color(0xFF818CF8)
                    : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? (isDark ? Colors.white : const Color(0xFF1E293B))
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SUB-VIEW 0: ACTIVE WIDGETS, REORDERING & SIZES
  // --------------------------------------------------------------------------
  Widget _buildActiveWidgetsReorderSection(
      bool isDark, List<DashboardWidgetDef> activeWidgets) {
    if (activeWidgets.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          children: [
            const Icon(Icons.widgets_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'لا توجد ودجات مفعلة على الشاشة الرئيسية',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'انتقل إلى متجر الودجات لاختيار البطاقات والإحصائيات التي ترغب في إضافتها.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => setState(() => _widgetStoreTab = 1),
              icon: const Icon(Icons.storefront_rounded, size: 18),
              label: const Text('تصفح متجر الودجات الآن'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Helper notice
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                const Color(0xFF6366F1).withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.tips_and_updates_rounded,
                  color: Color(0xFF818CF8), size: 19),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'اسحب المقبض ☰ لإعادة الترتيب. اختر مقاس العرض (عرض كامل 100%، نصف الشاشة 50% للتجاور، أو مدمج) لكل ودجت.',
                  style: TextStyle(fontSize: 11.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Quick action: Restore Defaults
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'الودجات المفعلة (${activeWidgets.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _restoreWidgetsDefaults,
              icon: const Icon(Icons.restart_alt_rounded,
                  size: 16, color: Color(0xFF94A3B8)),
              label: const Text(
                'استعادة الافتراضي',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Reorderable list
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: activeWidgets.length,
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final active =
                  _dashboardWidgets.where((w) => w.isEnabled).toList();
              final moved = active.removeAt(oldIndex);
              active.insert(newIndex, moved);

              final inactive =
                  _dashboardWidgets.where((w) => !w.isEnabled).toList();
              _dashboardWidgets = [...active, ...inactive];
            });
            _saveWidgetsConfig();
          },
          itemBuilder: (context, index) {
            final w = activeWidgets[index];
            return _buildActiveWidgetItemCard(w, index, isDark);
          },
        ),
      ],
    );
  }

  Widget _buildActiveWidgetItemCard(
      DashboardWidgetDef w, int index, bool isDark) {
    return Container(
      key: ValueKey('active_widget_${w.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D172A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              // Drag Handle
              ReorderableDragStartListener(
                index: index,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.drag_indicator_rounded,
                      color: Color(0xFF818CF8), size: 20),
                ),
              ),
              const SizedBox(width: 10),

              // Widget Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: w.iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(w.icon, color: w.iconColor, size: 20),
              ),
              const SizedBox(width: 10),

              // Title and category
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            w.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _getCategoryLabel(w.category),
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF818CF8),
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      w.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Remove from home button
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    color: Color(0xFFF87171), size: 20),
                tooltip: 'إزالة من الشاشة',
                onPressed: () => _toggleWidget(w),
              ),
            ],
          ),

          const Divider(height: 18, thickness: 1, color: Color(0x1F94A3B8)),

          // Size Controls Row
          Row(
            children: [
              Text(
                'مقاس العرض:',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildSizeChip(w, 'full', 'كامل 100%',
                          Icons.view_agenda_rounded, isDark),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildSizeChip(w, 'half', 'نصف 50%',
                          Icons.view_column_rounded, isDark),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildSizeChip(
                          w, 'compact', 'مدمج', Icons.compress_rounded, isDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSizeChip(DashboardWidgetDef def, String sizeKey, String label,
      IconData icon, bool isDark) {
    final isSelected = def.size == sizeKey;
    return InkWell(
      onTap: () => _changeWidgetSize(def, sizeKey),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withValues(alpha: isDark ? 0.25 : 0.12)
              : (isDark ? const Color(0xFF142036) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected
                    ? const Color(0xFF818CF8)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? (isDark ? Colors.white : const Color(0xFF4F46E5))
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SUB-VIEW 1: WIDGET STORE CATALOG
  // --------------------------------------------------------------------------
  Widget _buildWidgetStoreCatalogSection(bool isDark) {
    final categories = [
      {'id': 'all', 'label': 'الكل'},
      {'id': 'overview', 'label': 'نظرة عامة'},
      {'id': 'kpis', 'label': 'مؤشرات الأداء'},
      {'id': 'schedules', 'label': 'الجداول والحصص'},
      {'id': 'finances', 'label': 'الماليات والرسوم'},
      {'id': 'tools', 'label': 'الأدوات والمفكرة'},
    ];

    final filteredList = _dashboardWidgets.where((w) {
      final matchesCategory = _widgetSelectedCategory == 'all' ||
          w.category == _widgetSelectedCategory;
      final matchesQuery = _widgetSearchQuery.isEmpty ||
          w.title.contains(_widgetSearchQuery) ||
          w.subtitle.contains(_widgetSearchQuery);
      return matchesCategory && matchesQuery;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Bar
        TextField(
          controller: _widgetSearchController,
          style: const TextStyle(fontSize: 13.5),
          onChanged: (val) => setState(() => _widgetSearchQuery = val.trim()),
          decoration: InputDecoration(
            hintText:
                'ابحث في متجر الودجات (مثال: ماليات، غياب، جدول، مفكرة)...',
            hintStyle: TextStyle(
              fontSize: 12.5,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 20, color: Color(0xFF6366F1)),
            suffixIcon: _widgetSearchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _widgetSearchController.clear();
                      setState(() => _widgetSearchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: isDark ? const Color(0xFF0D172A) : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color:
                    isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: Color(0xFF6366F1), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Category Filter Chips
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final cat = categories[idx];
              final isSel = _widgetSelectedCategory == cat['id'];
              return ChoiceChip(
                label: Text(cat['label']!),
                selected: isSel,
                onSelected: (val) {
                  if (val) setState(() => _widgetSelectedCategory = cat['id']!);
                },
                selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.25),
                backgroundColor:
                    isDark ? const Color(0xFF0D172A) : Colors.white,
                side: BorderSide(
                  color: isSel
                      ? const Color(0xFF6366F1)
                      : (isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFCBD5E1)),
                  width: isSel ? 1.4 : 1.0,
                ),
                labelStyle: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  color: isSel
                      ? const Color(0xFF818CF8)
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),

        // Result count
        Text(
          'الودجات المتاحة (${filteredList.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
        const SizedBox(height: 10),

        // Catalog cards list
        if (filteredList.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D172A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'لم يتم العثور على أي ودجت يطابق بحثك',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredList.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, idx) {
              final w = filteredList[idx];
              return _buildStoreWidgetCard(w, isDark);
            },
          ),
      ],
    );
  }

  Widget _buildStoreWidgetCard(DashboardWidgetDef w, bool isDark) {
    final isAdded = w.isEnabled;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D172A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isAdded
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [w.iconColor.withValues(alpha: 0.8), w.iconColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: w.iconColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(w.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            w.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _getCategoryLabel(w.category),
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF818CF8),
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      w.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 18, thickness: 1, color: Color(0x1F94A3B8)),

          // Bottom Action Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF142036)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'المقاس: ${w.size == 'half' ? 'نصف 50%' : (w.size == 'compact' ? 'مدمج' : 'كامل 100%')}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isAdded)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    side: const BorderSide(color: Color(0x66F87171)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _toggleWidget(w),
                  icon:
                      const Icon(Icons.remove_circle_outline_rounded, size: 16),
                  label: const Text('إزالة من الشاشة',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11.5)),
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _toggleWidget(w),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('+ إضافة للشاشة',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11.5)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _getCategoryLabel(String catId) {
    switch (catId) {
      case 'overview':
        return 'نظرة عامة';
      case 'kpis':
        return 'مؤشرات الأداء';
      case 'schedules':
        return 'الجداول والحصص';
      case 'finances':
        return 'الماليات';
      case 'tools':
        return 'أدوات ومفكرة';
      default:
        return 'عام';
    }
  }

  // ==========================================================================
  // TAB 3: PROFILE SETTINGS (الملف الشخصي)
  // ==========================================================================
  Widget buildProfileSettingsTab(bool isDark, Color primaryColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        children: [
          // --- 1. Photo Upload Hero Card ---
          _buildPhotoHeroCard(isDark, primaryColor),
          const SizedBox(height: 18),

          _buildCardWrapper(
            isDark: isDark,
            title: 'بيانات السنتر / الأكاديمية',
            icon: Icons.apartment_rounded,
            iconColor: const Color(0xFF10B981),
            children: [
              _buildInputField(
                controller: _centerNameController,
                label: 'اسم السنتر أو الأكاديمية',
                hint: 'مثال: أكاديمية المستقبل',
                icon: Icons.apartment_rounded,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // --- 2. Personal & Professional Details ---
          _buildCardWrapper(
            isDark: isDark,
            title: 'البيانات الأساسية والمهنية',
            icon: Icons.badge_rounded,
            iconColor: const Color(0xFF38BDF8),
            children: [
              _buildInputField(
                controller: _nameController,
                label: 'اسم المعلم / المحاضر',
                hint: 'مثال: أ. أحمد السيد',
                icon: Icons.person_outline_rounded,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _buildInputField(
                controller: _titleController,
                label: 'المسمى الوظيفي / التخصص',
                hint: 'مثال: خبير أول رياضيات وفيزياء',
                icon: Icons.school_outlined,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _buildInputField(
                controller: _bioController,
                label: 'النبذة التعريفية والخبرات',
                hint: 'اكتب نبذة مختصرة عن مسيرتك التدريسية وخبراتك...',
                icon: Icons.notes_rounded,
                isDark: isDark,
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // --- 3. Contact & Channels Details ---
          _buildCardWrapper(
            isDark: isDark,
            title: 'قنوات التواصل والتفاعل',
            icon: Icons.contact_phone_rounded,
            iconColor: const Color(0xFF10B981),
            children: [
              _buildInputField(
                controller: _phoneController,
                label: 'رقم هاتف العمل / واتساب',
                hint: '010XXXXXXXX',
                icon: Icons.phone_outlined,
                isDark: isDark,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              _buildInputField(
                controller: _emailController,
                label: 'البريد الإلكتروني الرسمي',
                hint: 'teacher@edu-academy.com',
                icon: Icons.alternate_email_rounded,
                isDark: isDark,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              _buildInputField(
                controller: _facebookController,
                label: 'رابط صفحة فيسبوك أو المجموعة',
                hint: 'https://facebook.com/...',
                icon: Icons.public_rounded,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _buildInputField(
                controller: _youtubeController,
                label: 'رابط قناة يوتيوب التعليمية',
                hint: 'https://youtube.com/@...',
                icon: Icons.play_circle_outline_rounded,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // --- Save Button ---
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F2FE),
                foregroundColor: const Color(0xFF021024),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: const Color(0x6600F2FE),
              ),
              onPressed: _isSaving ? null : _saveProfileChanges,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF021024)),
                    )
                  : const Icon(Icons.check_circle_rounded, size: 22),
              label: Text(
                _isSaving ? 'جاري الحفظ...' : 'حفظ تعديلات الملف الشخصي',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoHeroCard(bool isDark, Color primaryColor) {
    final bool hasPhoto = _photoPath != null && _photoPath!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D172A) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0x3338BDF8) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Circular Avatar with Glow
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00F2FE), Color(0xFF0284C7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00F2FE)
                            .withValues(alpha: isDark ? 0.4 : 0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3.5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF080E1C) : Colors.white,
                    ),
                    child: ClipOval(
                      child: hasPhoto
                          ? Image.file(
                              File(_photoPath!),
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            )
                          : const Center(
                              child: Text(
                                '👨‍🏫',
                                style: TextStyle(fontSize: 48),
                              ),
                            ),
                    ),
                  ),
                ),
                // Camera Icon Action Badge
                InkWell(
                  onTap: _pickPhotoFromPhone,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF080E1C) : Colors.white,
                        width: 2.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 16, color: Color(0xFF021024)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Text(
            _nameController.text.isNotEmpty
                ? _nameController.text
                : 'أ. أحمد السيد',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 3),
          Text(
            _titleController.text.isNotEmpty
                ? _titleController.text
                : 'خبير ومحاضر أول',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),

          // Upload and Remove Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF00F2FE).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFF00F2FE),
                  elevation: 0,
                  side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: _pickPhotoFromPhone,
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                label: Text(
                  hasPhoto ? 'تغيير الصورة' : 'رفع صورة من الهاتف',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              if (hasPhoto) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    side: const BorderSide(color: Color(0x66F87171)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onPressed: _removePhoto,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text(
                    'حذف',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardWrapper({
    required bool isDark,
    required String title,
    required IconData icon,
    required Color iconColor,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const Divider(height: 24, thickness: 1, color: Color(0x1F94A3B8)),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
            prefixIcon: Icon(icon, size: 20, color: const Color(0xFF64748B)),
            suffixIcon: keyboardType == TextInputType.phone
                ? IconButton(
                    icon: const Icon(Icons.contacts_rounded,
                        color: Color(0xFF10B981), size: 20),
                    tooltip: 'اختيار من دليل الهاتف',
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      final contact = await ContactPickerService.pickContact();
                      if (contact != null && contact.phone.isNotEmpty) {
                        controller.text = contact.phone;
                      }
                    },
                  )
                : null,
            filled: true,
            fillColor:
                isDark ? const Color(0xFF142036) : const Color(0xFFF1F5F9),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 3: WHATSAPP INTEGRATION & AUTOMATION (إدارة واتساب والربط الذكي)
  // ==========================================================================
  Widget _buildWhatsAppSettingsTab(bool isDark, Color primaryColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          _buildWhatsAppHeroBanner(isDark),
          const SizedBox(height: 18),

          // 1. Dispatch Mode Selection
          _buildWaModeSelector(isDark),
          const SizedBox(height: 18),

          // 2. API & Gateway Credentials
          _buildWaApiConfigCard(isDark),
          const SizedBox(height: 18),

          // 3. Anti-Ban Protection & Message Delays
          _buildWaAntiBanCard(isDark),
          const SizedBox(height: 18),

          // 4. Message Footer / Signature
          _buildWaFooterCard(isDark),
          const SizedBox(height: 18),

          // 5. Session Report Master Template
          _buildWaMasterTemplateCard(isDark),
          const SizedBox(height: 18),

          // 6. Guardian Notification Automation Switches
          _buildWaAlertsTogglesCard(isDark),
          const SizedBox(height: 24),

          // 5. Save Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: const Color(0xFF021024),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: const Color(0x6625D366),
              ),
              onPressed: _isSaving ? null : _saveWhatsAppChanges,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF021024)),
                    )
                  : const Icon(Icons.check_circle_rounded, size: 22),
              label: Text(
                _isSaving ? 'جاري الحفظ...' : 'حفظ إعدادات وبوابة واتساب',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppHeroBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF082218), Color(0xFF0A192F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFE8FDF0), Color(0xFFF0FDF4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF25D366).withValues(alpha: isDark ? 0.35 : 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF25D366).withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF25D366), Color(0xFF128C7E)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF25D366).withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.chat_bubble_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'منظومة واتساب الذكية للرسائل',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                SizedBox(height: 3),
                Text(
                  'ربط الـ API للرسائل التلقائية، درع مكافحة الحظر وتأخير الإرسال، وتخصيص تنبيهات أولياء الأمور.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaModeSelector(bool isDark) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'وضع الإرسال وطريقة التوصيل',
      icon: Icons.alt_route_rounded,
      iconColor: const Color(0xFF38BDF8),
      children: [
        _buildModeOption(
          isDark: isDark,
          mode: 'manual',
          title: 'تطبيق واتساب الرسمي (يدوي)',
          subtitle:
              'يفتح تطبيق واتساب على الهاتف وتجهيز نص الرسالة لكل ولي أمر مع كل إشعار بدون اشتراكات أو سيرفر خارجي.',
          icon: Icons.phone_android_rounded,
        ),
        const SizedBox(height: 10),
        _buildModeOption(
          isDark: isDark,
          mode: 'api',
          title: 'إرسال آلي وتلقائي عبر API (بدون فتح التطبيق)',
          subtitle:
              'إرسال صامت فوري في الخلفية عبر خوادم الـ Webhook و REST API مثل UltraMsg أو Evolution أو سيرفرك الخاص.',
          icon: Icons.cloud_done_rounded,
        ),
        if (_waMode == 'manual') ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.apps_rounded, size: 16, color: Color(0xFF25D366)),
              SizedBox(width: 6),
              Text(
                'نسخة واتساب المفضلة على جهازك:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'auto',
                label: Text('تلقائي', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: 'com.whatsapp',
                label: Text('WhatsApp العادي', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: 'com.whatsapp.w4b',
                label: Text('WhatsApp للأعمال', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: {_waAppPackage},
            onSelectionChanged: (set) {
              setState(() {
                _waAppPackage = set.first;
              });
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeOption({
    required bool isDark,
    required String mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _waMode == mode;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _waMode = mode);
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF25D366).withValues(alpha: isDark ? 0.14 : 0.08)
              : (isDark ? const Color(0xFF142036) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF25D366)
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF25D366).withValues(alpha: 0.2)
                    : (isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF25D366)
                    : const Color(0xFF94A3B8),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isSelected
                          ? (isDark
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFF15803D))
                          : (isDark ? Colors.white : const Color(0xFF1E293B)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected
                  ? const Color(0xFF25D366)
                  : const Color(0xFF64748B),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaApiConfigCard(bool isDark) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'بيانات بوابة الـ API ومفاتيح الربط',
      icon: Icons.vpn_key_rounded,
      iconColor: const Color(0xFFF59E0B),
      children: [
        if (_waMode != 'api')
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B)
                  .withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFFF59E0B), size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'وضع الإرسال الحالي: يدوي (تطبيق واتساب)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFFF59E0B)),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'لكي يتم إرسال الرسائل عبر الـ API تلقائياً، اضغط لتفعيل وضع الـ API.',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(64, 34),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _waMode = 'api');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'تم تفعيل وضع الإرسال التلقائي عبر API (تذكر حفظ التغييرات بالأسفل)'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('تفعيل API',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981)
                  .withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Color(0xFF10B981), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'وضع الإرسال التلقائي عبر API مفعّل حالياً بنجاح ✅',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981)),
                  ),
                ),
              ],
            ),
          ),

        // Provider Selection Chips
        Text(
          'مزود خدمة الـ API (Provider)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildProviderChip('whatspro', 'واتس برو (Whats-Pro)', isDark),
            _buildProviderChip('custom', 'سيرفر مخصص (Custom)', isDark),
            _buildProviderChip('ultramsg', 'UltraMsg', isDark),
            _buildProviderChip('evolution', 'Evolution API', isDark),
            _buildProviderChip('wassenger', 'Wassenger', isDark),
          ],
        ),
        const SizedBox(height: 14),

        // Helpful guidance for Whats-Pro
        if (_waProvider == 'whatspro' ||
            _waEndpointController.text.contains('whats-pro'))
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7)
                  .withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_rounded,
                    color: Color(0xFF38BDF8), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'دليل ربط بوابة واتس برو (Whats-Pro):',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF38BDF8)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '1. رابط الـ Endpoint: تم ضبطه تلقائياً للإرسال المباشر (messages/send).\n'
                        '2. معرف النسخة (Instance ID): 🟢 غير مطلوب في Whats-Pro، اتركه فارغاً تماماً!\n'
                        '3. رمز التوثيق (Token): فقط الصق الرمز السري (Token) الخاص بحسابك من whats-pro.net.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Endpoint
        _buildInputField(
          controller: _waEndpointController,
          label: 'رابط الـ API المباشر (Endpoint URL)',
          hint: _getProviderEndpointHint(),
          icon: Icons.link_rounded,
          isDark: isDark,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 14),

        // Token / API Key with toggle visibility
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'رمز التوثيق / الـ Token / API Key',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color:
                    isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _waApiKeyController,
              obscureText: _waHideApiKey,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'أدخل رمز الـ Token أو Secret Key...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.key_rounded,
                    size: 20, color: Color(0xFF64748B)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _waHideApiKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: const Color(0xFF94A3B8),
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _waHideApiKey = !_waHideApiKey),
                ),
                filled: true,
                fillColor:
                    isDark ? const Color(0xFF142036) : const Color(0xFFF1F5F9),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFF25D366), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Instance ID
        _buildInputField(
          controller: _waInstanceController,
          label: (_waProvider == 'whatspro' ||
                  _waEndpointController.text.contains('whats-pro'))
              ? 'معرف النسخة (Instance ID) - [غير مطلوب لـ Whats-Pro، اتركه فارغاً]'
              : 'معرف النسخة / المعرف التعريفي (Instance ID)',
          hint: (_waProvider == 'whatspro' ||
                  _waEndpointController.text.contains('whats-pro'))
              ? 'اتركه فارغاً (غير مطلوب في Whats-Pro)'
              : 'مثال: instance12345 أو اسم الـ Instance',
          icon: Icons.devices_other_rounded,
          isDark: isDark,
        ),
        const SizedBox(height: 16),

        // Test Connection Button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF25D366),
              side: const BorderSide(color: Color(0xFF25D366), width: 1.2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              backgroundColor: const Color(0xFF25D366)
                  .withValues(alpha: isDark ? 0.08 : 0.05),
            ),
            onPressed: _isTestingWa ? null : _testWhatsAppConnection,
            icon: _isTestingWa
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF25D366)),
                  )
                : const Icon(Icons.wifi_tethering_rounded, size: 20),
            label: Text(
              _isTestingWa
                  ? 'جاري فحص الاتصال...'
                  : 'اختبار الاتصال وإرسال رسالة تجريبية',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProviderChip(String id, String label, bool isDark) {
    final isSelected = _waProvider == id;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() {
            _waProvider = id;
            final inst = _waInstanceController.text.trim().isNotEmpty
                ? _waInstanceController.text.trim()
                : 'instanceXXXXX';
            if (id == 'whatspro') {
              _waEndpointController.text =
                  'https://whats-pro.net/backend/public/index.php/api/messages/send';
              _waInstanceController.clear();
            } else if (id == 'ultramsg') {
              if (_waEndpointController.text.trim().isEmpty ||
                  !_waEndpointController.text.contains('ultramsg')) {
                _waEndpointController.text =
                    'https://api.ultramsg.com/$inst/messages/chat';
              }
            } else if (id == 'evolution') {
              if (_waEndpointController.text.trim().isEmpty ||
                  !_waEndpointController.text.contains('message/sendText')) {
                final evInst = _waInstanceController.text.trim().isNotEmpty
                    ? _waInstanceController.text.trim()
                    : 'instance_name';
                _waEndpointController.text =
                    'https://your-server.com/message/sendText/$evInst';
              }
            } else if (id == 'wassenger') {
              if (_waEndpointController.text.trim().isEmpty ||
                  !_waEndpointController.text.contains('wassenger')) {
                _waEndpointController.text =
                    'https://api.wassenger.com/v1/messages';
              }
            }
          });
        }
      },
      selectedColor: const Color(0xFF25D366).withValues(alpha: 0.25),
      backgroundColor:
          isDark ? const Color(0xFF142036) : const Color(0xFFF1F5F9),
      side: BorderSide(
        color: isSelected
            ? const Color(0xFF25D366)
            : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
        width: isSelected ? 1.4 : 1.0,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected
            ? const Color(0xFF25D366)
            : (isDark ? Colors.white70 : Colors.black87),
      ),
    );
  }

  String _getProviderEndpointHint() {
    switch (_waProvider) {
      case 'whatspro':
        return 'https://whats-pro.net/backend/public/index.php/api/messages/send';
      case 'ultramsg':
        return 'https://api.ultramsg.com/instanceXXXXX/messages/chat';
      case 'evolution':
        return 'https://api.example.com/message/sendText/instance_name';
      case 'wassenger':
        return 'https://api.wassenger.com/v1/messages';
      default:
        return 'https://your-domain.com/api/send-whatsapp';
    }
  }

  Widget _buildWaAntiBanCard(bool isDark) {
    Color safetyColor;
    String safetyTitle;
    IconData safetyIcon;

    if (_waDelaySeconds < 5) {
      safetyColor = const Color(0xFFF59E0B);
      safetyTitle =
          '⚠️ إرسال سريع (يُفضل استخدامه للمجموعات الصغيرة فقط تجنباً للملاحظة)';
      safetyIcon = Icons.speed_rounded;
    } else if (_waDelaySeconds <= 10) {
      safetyColor = const Color(0xFF10B981);
      safetyTitle =
          '🛡️ الوضع الآمن الموصى به رسمياً لحماية رقمك من قيود الحظر';
      safetyIcon = Icons.verified_user_rounded;
    } else {
      safetyColor = const Color(0xFF00F2FE);
      safetyTitle = '🔒 حماية قصوى للأعداد الضخمة ومجموعات الطلاب الكبيرة';
      safetyIcon = Icons.shield_rounded;
    }

    return _buildCardWrapper(
      isDark: isDark,
      title: 'درع مكافحة الحظر وتأخير الإرسال (Anti-Ban)',
      icon: Icons.shield_rounded,
      iconColor: const Color(0xFF10B981),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'الفاصل الزمني بين الرسائل:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: safetyColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: safetyColor, width: 1.2),
              ),
              child: Text(
                '$_waDelaySeconds ثوانٍ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: safetyColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: safetyColor,
            inactiveTrackColor:
                isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            thumbColor: safetyColor,
            overlayColor: safetyColor.withValues(alpha: 0.2),
            trackHeight: 4,
          ),
          child: Slider(
            value: _waDelaySeconds.toDouble(),
            min: 2,
            max: 25,
            divisions: 23,
            onChanged: (val) {
              setState(() => _waDelaySeconds = val.round());
            },
          ),
        ),

        // Safety Status Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: safetyColor.withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: safetyColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(safetyIcon, color: safetyColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  safetyTitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: safetyColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'ملاحظة: تفرض خوارزميات واتساب حظراً مؤقتاً أو دائماً على الأرقام التي ترسل عدداً كبيراً من الرسائل في أجزاء من الثانية. إبقاء الفاصل الزمني فوق 5 ثوانٍ يضمن عدم تصنيف رسائلك كرسائل مزعجة (Spam).',
          style: TextStyle(
            fontSize: 11,
            height: 1.45,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildWaFooterCard(bool isDark) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'خاتمة وتذييل رسائل الواتساب (Footer / Signature)',
      icon: Icons.border_bottom_rounded,
      iconColor: const Color(0xFF00F2FE),
      children: [
        _buildAlertSwitchTile(
          isDark: isDark,
          title: 'تفعيل الخاتمة التلقائية لجميع الرسائل',
          subtitle:
              'إرفاق التوقيع وبيانات السنتر تلقائياً أسفل كل رسالة (الغياب، الدرجات، الإيصالات، رسائل الـ Hub).',
          icon: Icons.auto_awesome_rounded,
          iconColor: const Color(0xFF25D366),
          value: _waEnableFooter,
          onChanged: (v) async {
            setState(() => _waEnableFooter = v);
            await widget.database
                .setSetting('whatsapp_enable_footer', v.toString());
            widget.database.notifyChange(DataChangeEvent.settings);
          },
        ),
        if (_waEnableFooter) ...[
          const Divider(height: 24, color: Color(0x1F94A3B8)),
          const Text(
            'قوالب سريعة مقترحة للتذييل:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFooterTemplateChip(
                  label: '🏛 بيانات السنتر والدعم',
                  isDark: isDark,
                  onTap: () async {
                    final name = _nameController.text.trim().isNotEmpty
                        ? _nameController.text.trim()
                        : 'سنتر التفوق التعليمي';
                    final phone = _phoneController.text.trim().isNotEmpty
                        ? _phoneController.text.trim()
                        : '';
                    final pPart =
                        phone.isNotEmpty ? '\n📞 للتواصل: $phone' : '';
                    final txt = '---\n📍 $name$pPart';
                    setState(() {
                      _waFooterController.text = txt;
                    });
                    await widget.database
                        .setSetting('whatsapp_message_footer', txt);
                    widget.database.notifyChange(DataChangeEvent.settings);
                  },
                ),
                const SizedBox(width: 8),
                _buildFooterTemplateChip(
                  label: '⭐ تمنيات بالتفوق والنجاح',
                  isDark: isDark,
                  onTap: () async {
                    const txt =
                        '✨ مع خالص تمنياتنا لجميع الطلاب بدوام التوفيق والتفوق ✨\nإدارة المتابعة والأكاديمية';
                    setState(() {
                      _waFooterController.text = txt;
                    });
                    await widget.database
                        .setSetting('whatsapp_message_footer', txt);
                    widget.database.notifyChange(DataChangeEvent.settings);
                  },
                ),
                const SizedBox(width: 8),
                _buildFooterTemplateChip(
                  label: '📌 إشعار نظام رسمي',
                  isDark: isDark,
                  onTap: () async {
                    const txt =
                        '━━━━━━━━━━━━━━━\n📌 هذا الإشعار تم إرساله آلياً من نظام إدارة الأكاديمية.';
                    setState(() {
                      _waFooterController.text = txt;
                    });
                    await widget.database
                        .setSetting('whatsapp_message_footer', txt);
                    widget.database.notifyChange(DataChangeEvent.settings);
                  },
                ),
                const SizedBox(width: 8),
                _buildFooterTemplateChip(
                  label: '🗑 مسح الخاتمة',
                  isDark: isDark,
                  color: const Color(0xFFEF4444),
                  onTap: () async {
                    setState(() {
                      _waFooterController.clear();
                    });
                    await widget.database
                        .setSetting('whatsapp_message_footer', '');
                    widget.database.notifyChange(DataChangeEvent.settings);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _waFooterController,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(fontSize: 13, height: 1.4),
            onChanged: (val) async {
              setState(() {});
              await widget.database
                  .setSetting('whatsapp_message_footer', val.trim());
              widget.database.notifyChange(DataChangeEvent.settings);
            },
            decoration: InputDecoration(
              labelText: 'نص التذييل / الخاتمة (Footer)',
              hintText:
                  'اكتب نص التذييل الذي سيظهر أسفل جميع الرسائل...\nمثال: سنتر التفوق - هاتف: 01xxxxxxxxx',
              alignLabelWithHint: true,
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF25D366), width: 1.5),
              ),
              suffixIcon: _waFooterController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      tooltip: 'مسح',
                      onPressed: () async {
                        setState(() => _waFooterController.clear());
                        await widget.database
                            .setSetting('whatsapp_message_footer', '');
                        widget.database.notifyChange(DataChangeEvent.settings);
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          // Live Preview Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF081C15) : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF25D366).withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.preview_rounded,
                        size: 16, color: Color(0xFF25D366)),
                    const SizedBox(width: 6),
                    Text(
                      'معاينة حية لشكل الرسالة مع الخاتمة:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'السلام عليكم ولي أمر الطالب...\n(محتوى رسالة الغياب أو التقرير أو الإيصال)',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                if (_waFooterController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF25D366).withValues(alpha: 0.25),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Text(
                      _waFooterController.text.trim(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF15803D),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    '⚠️ لم تقم بكتابة خاتمة بعد. لن يضاف تذييل للرسائل.',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: isDark
                          ? Colors.amber.shade300
                          : Colors.amber.shade900,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final txt = _waFooterController.text.trim();
                await widget.database
                    .setSetting('whatsapp_message_footer', txt);
                await widget.database.setSetting(
                    'whatsapp_enable_footer', _waEnableFooter.toString());
                widget.database.notifyChange(DataChangeEvent.settings);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                      content: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('تم حفظ وتطبيق الخاتمة بنجاح لجميع الرسائل ✅'),
                        ],
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('حفظ وتطبيق الخاتمة فوراً',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFooterTemplateChip({
    required String label,
    required bool isDark,
    required VoidCallback onTap,
    Color? color,
  }) {
    final chipColor = color ?? const Color(0xFF00F2FE);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: chipColor.withValues(alpha: 0.4), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: chipColor,
          ),
        ),
      ),
    );
  }

  Widget _buildWaMasterTemplateCard(bool isDark) {
    const emeraldColor = Color(0xFF059669);
    final tags = [
      {'tag': '{اسم_الطالب}', 'label': 'اسم الطالب 👤'},
      {'tag': '{حالة_الحضور}', 'label': 'حالة الحضور 📍'},
      {'tag': '{موضوع_الدرس}', 'label': 'موضوع الدرس 📖'},
      {'tag': '{عناصر_الشرح}', 'label': 'عناصر الشرح 📝'},
      {'tag': '{الواجب}', 'label': 'الواجب المطلوب 📚'},
      {'tag': '{كويز_الحصة_القادمة}', 'label': 'كويز القادم 🎯'},
      {'tag': '{تقييم_الواجب}', 'label': 'تقييم الواجب السابق ✏️'},
      {'tag': '{ملاحظات_الواجب}', 'label': 'ملاحظات الواجب 🗒️'},
      {'tag': '{تقييم_التسميع}', 'label': 'تقييم التسميع ⭐'},
      {'tag': '{موضوع_المراجعة}', 'label': 'موضوع المراجعة 🔄'},
      {'tag': '{ملاحظات}', 'label': 'ملاحظات المعلم 💡'},
      {'tag': '{المجموعة}', 'label': 'اسم المجموعة 👥'},
      {'tag': '{التاريخ}', 'label': 'التاريخ 📅'},
      {'tag': '{السنتر}', 'label': 'السنتر 🏛️'},
      {'tag': '{المعلم}', 'label': 'المعلم 👨‍🏫'},
    ];

    void insertTag(String tag) {
      final text = _waReportTemplateController.text;
      final selection = _waReportTemplateController.selection;
      if (selection.start >= 0 && selection.end >= 0) {
        final newText = text.replaceRange(selection.start, selection.end, tag);
        _waReportTemplateController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: selection.start + tag.length),
        );
      } else {
        _waReportTemplateController.text = text + tag;
      }
      setState(() {});
    }

    return _buildCardWrapper(
      isDark: isDark,
      title: 'النموذج العام لتقارير متابعة الحصص 📋',
      icon: Icons.article_rounded,
      iconColor: const Color(0xFF10B981),
      children: [
        Text(
          'تخصيص القالب العام المعتمد لجميع رسائل تقارير الحصص لأولياء الأمور. التعديل هنا يُعتمد لجميع الطلاب في كافة المجموعات:',
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'اضغط لإدراج المتغير في مكان المؤشر:',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tags.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              final t = tags[i];
              return ActionChip(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                label: Text(
                  t['label']!,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                side: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  width: 0.8,
                ),
                onPressed: () => insertTag(t['tag']!),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _waReportTemplateController,
          maxLines: 12,
          minLines: 6,
          style: const TextStyle(fontSize: 12.5, height: 1.45),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            hintText: 'اكتب نص النموذج العام هنا...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber.shade800,
                side: BorderSide(color: Colors.amber.shade700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              icon: const Icon(Icons.restore_rounded, size: 16),
              label: const Text('الافتراضي 🔄', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              onPressed: () {
                setState(() {
                  _waReportTemplateController.text = WhatsAppService.defaultSessionReportTemplate;
                });
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: emeraldColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text(
                  'حفظ واعتماد النموذج العام 💾',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final newText = _waReportTemplateController.text.trim();
                  await widget.database.setSetting(
                    'whatsapp_template_session_report',
                    newText,
                  );
                  widget.database.notifyChange(DataChangeEvent.settings);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حفظ واعتماد النموذج العام لتقارير الحصص بنجاح ✅'),
                        backgroundColor: Color(0xFF059669),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWaAlertsTogglesCard(bool isDark) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'خيارات تنبيهات وإشعارات أولياء الأمور',
      icon: Icons.notifications_active_rounded,
      iconColor: const Color(0xFF00F2FE),
      children: [
        const Text(
          'حدد الأحداث التي يتم إرسال تنبيهات تلقائية لها لولي الأمر فور تسجيلها في التطبيق:',
          style: TextStyle(fontSize: 11.5, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _waMode == 'api'
                ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.15 : 0.08)
                : Colors.amber.withValues(alpha: isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _waMode == 'api'
                  ? const Color(0xFF10B981).withValues(alpha: 0.4)
                  : Colors.amber.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _waMode == 'api' ? Icons.bolt_rounded : Icons.info_outline_rounded,
                size: 18,
                color: _waMode == 'api' ? const Color(0xFF10B981) : Colors.amber.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _waMode == 'api'
                      ? 'وضع الإرسال الآلي (API) مفعل: التنبيهات المحددة بالأسفل ستُرسل فورياً وصامتاً في الخلفية بدون فتح التطبيق.'
                      : 'وضع الإرسال محدد على "يدوي": التنبيهات الآلية لا تُرسل في الخلفية منعاً لمقاطعتك، ولكن يمكنك إرسالها جماعياً أو فردياً من مركز رسائل واتساب. للإرسال التلقائي الصامت فعّل وضع الـ API.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: _waMode == 'api'
                        ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46))
                        : (isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildAlertSwitchTile(
          isDark: isDark,
          title: 'إنذار الغياب الفوري',
          subtitle:
              'إشعار فوري لولي الأمر عند تسجيل الطالب غائباً في الحصة لمنع التهرب.',
          icon: Icons.event_busy_rounded,
          iconColor: const Color(0xFFEF4444),
          value: _waAlertAbsence,
          onChanged: (v) => setState(() => _waAlertAbsence = v),
        ),
        const Divider(height: 18, color: Color(0x1F94A3B8)),
        _buildAlertSwitchTile(
          isDark: isDark,
          title: 'إشعار تسجيل الحضور بأمان',
          subtitle:
              'إرسال تأكيد لولي الأمر عند مسح كود الطالب وبدء الحصة للاطمئنان.',
          icon: Icons.how_to_reg_rounded,
          iconColor: const Color(0xFF10B981),
          value: _waAlertCheckin,
          onChanged: (v) => setState(() => _waAlertCheckin = v),
        ),
        const Divider(height: 18, color: Color(0x1F94A3B8)),
        _buildAlertSwitchTile(
          isDark: isDark,
          title: 'بطاقة درجات الامتحانات',
          subtitle:
              'إرسال بطاقة درجات الطالب والنسبة المئوية والملاحظات عند اعتماد الامتحان.',
          icon: Icons.grade_rounded,
          iconColor: const Color(0xFFF59E0B),
          value: _waAlertExamScores,
          onChanged: (v) => setState(() => _waAlertExamScores = v),
        ),
        const Divider(height: 18, color: Color(0x1F94A3B8)),
        _buildAlertSwitchTile(
          isDark: isDark,
          title: 'إيصالات السداد والمطالبات المالية',
          subtitle:
              'إرسال سندات استلام الرسوم أو إشعارات بالمستحقات المالية المتبقية.',
          icon: Icons.receipt_long_rounded,
          iconColor: const Color(0xFF8B5CF6),
          value: _waAlertFinancialReceipt,
          onChanged: (v) => setState(() => _waAlertFinancialReceipt = v),
        ),
        const Divider(height: 18, color: Color(0x1F94A3B8)),
        _buildAlertSwitchTile(
          isDark: isDark,
          title: 'تذكير بموعد الحصة القادمة',
          subtitle: 'تذكير مسبق للطلاب بمواعيد الحصص والمراجعات الهامة.',
          icon: Icons.alarm_rounded,
          iconColor: const Color(0xFF06B6D4),
          value: _waAlertSessionReminder,
          onChanged: (v) => setState(() => _waAlertSessionReminder = v),
        ),
        const Divider(height: 18, color: Color(0x1F94A3B8)),
        _buildAlertSwitchTile(
          isDark: isDark,
          title: 'ملاحظات الواجب والتسميع والسلوك',
          subtitle:
              'إرسال ملخص تقييم الطالب في الواجب المنزلي والتسميع والالتزام.',
          icon: Icons.assignment_turned_in_rounded,
          iconColor: const Color(0xFFEC4899),
          value: _waAlertBehavior,
          onChanged: (v) => setState(() => _waAlertBehavior = v),
        ),
      ],
    );
  }

  Widget _buildAlertSwitchTile({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch.adaptive(
          value: value,
          activeTrackColor: const Color(0xFF25D366).withValues(alpha: 0.35),
          onChanged: onChanged,
        ),
      ],
    );
  }



  Future<void> _saveWhatsAppChanges() async {
    setState(() => _isSaving = true);

    await widget.database.setSetting('whatsapp_mode', _waMode);
    await widget.database.setSetting('whatsapp_app_package', _waAppPackage);
    await widget.database.setSetting('whatsapp_api_provider', _waProvider);
    await widget.database
        .setSetting('whatsapp_api_endpoint', _waEndpointController.text.trim());
    await widget.database
        .setSetting('whatsapp_api_key', _waApiKeyController.text.trim());
    await widget.database
        .setSetting('whatsapp_api_instance', _waInstanceController.text.trim());
    await widget.database
        .setSetting('whatsapp_send_delay_seconds', _waDelaySeconds.toString());

    // Alerts - save both wa_alert_* and legacy whatsapp_auto_send_*
    await widget.database
        .setSetting('wa_alert_absence', _waAlertAbsence.toString());
    await widget.database
        .setSetting('whatsapp_auto_send_absence', _waAlertAbsence.toString());

    await widget.database
        .setSetting('wa_alert_checkin', _waAlertCheckin.toString());
    await widget.database.setSetting(
        'whatsapp_auto_send_attendance', _waAlertCheckin.toString());

    await widget.database
        .setSetting('wa_alert_exam_scores', _waAlertExamScores.toString());
    await widget.database
        .setSetting('whatsapp_auto_send_exam', _waAlertExamScores.toString());

    await widget.database.setSetting(
        'wa_alert_financial_receipt', _waAlertFinancialReceipt.toString());
    await widget.database.setSetting(
        'whatsapp_auto_send_payment', _waAlertFinancialReceipt.toString());

    await widget.database.setSetting(
        'wa_alert_session_reminder', _waAlertSessionReminder.toString());
    await widget.database
        .setSetting('wa_alert_behavior', _waAlertBehavior.toString());

    // Message Footer / Signature
    await widget.database
        .setSetting('whatsapp_message_footer', _waFooterController.text.trim());
    await widget.database
        .setSetting('whatsapp_enable_footer', _waEnableFooter.toString());
    await widget.database.setSetting(
        'whatsapp_template_session_report', _waReportTemplateController.text.trim());

    widget.database.notifyChange(DataChangeEvent.settings);

    if (mounted) {
      setState(() => _isSaving = false);
      final isApi = _waMode == 'api';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF10B981),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.task_alt_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isApi
                      ? 'تم حفظ الإعدادات وتفعيل وضع الإرسال التلقائي عبر API ✅'
                      : 'تم حفظ إعدادات واتساب (الوضع اليدوي) بنجاح ✅',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _testWhatsAppConnection() async {
    var endpoint = _waEndpointController.text.trim();
    if (endpoint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text('يرجى إدخال رابط API الخاص بك أولاً'),
        ),
      );
      return;
    }

    final isWhatsPro =
        _waProvider == 'whatspro' || endpoint.contains('whats-pro');

    // Auto-fix truncated Whats-Pro URL if user pasted backend/p or old send path
    if (isWhatsPro) {
      if (!endpoint.contains('/messages/send')) {
        endpoint =
            'https://whats-pro.net/backend/public/index.php/api/messages/send';
        _waEndpointController.text = endpoint;
      }
    }

    final isInstanceEmpty = _waInstanceController.text.trim().isEmpty;

    final testPhoneController =
        TextEditingController(text: _phoneController.text.trim());
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x3338BDF8)),
          ),
          title: const Row(
            children: [
              Icon(Icons.wifi_tethering_rounded, color: Color(0xFF25D366)),
              SizedBox(width: 10),
              Text(
                'اختبار بوابة الـ API',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'سيتم إرسال رسالة تجريبية للتأكد من صحة الـ API والـ Token المُدخلين وسلامة الربط.',
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              if (!isWhatsPro &&
                  isInstanceEmpty &&
                  (_waProvider == 'ultramsg' ||
                      _waProvider == 'evolution')) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFF59E0B), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تنبيه: خانة معرف النسخة (Instance ID) فارغة! تتطلب بوابات UltraMsg / Evolution إدخال معرف النسخة لتوجيه الرسالة.',
                          style: TextStyle(
                              color: Color(0xFFF59E0B),
                              fontSize: 11.5,
                              height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: testPhoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'رقم الهاتف للتجربة (مع كود الدولة)',
                  labelStyle:
                      const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  hintText: 'مثال: 201012345678',
                  hintStyle:
                      const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.phone_rounded,
                      color: Color(0xFF25D366), size: 18),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.contacts_rounded,
                        color: Color(0xFF25D366), size: 20),
                    tooltip: 'اختيار من دليل الهاتف',
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      final contact = await ContactPickerService.pickContact();
                      if (contact != null && contact.phone.isNotEmpty) {
                        final formatted =
                            WhatsAppService.formatPhone(contact.phone);
                        testPhoneController.text = formatted;
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إرسال تجربة الآن'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    final targetPhone = testPhoneController.text.trim();
    if (targetPhone.isEmpty) return;

    final waFooter = _waFooterController.text.trim();
    final waEnable = _waEnableFooter;
    var testMsg =
        'مرحباً، هذه رسالة تجريبية ناجحة من منصة Edu Academy للتحقق من ربط بوابة الـ API.';
    if (waEnable && waFooter.isNotEmpty) {
      testMsg = '$testMsg\n\n$waFooter';
    }

    setState(() => _isTestingWa = true);
    try {
      final res = await WhatsAppService.sendViaApi(
        endpointUrl: endpoint,
        apiKey: _waApiKeyController.text.trim(),
        instanceId: _waInstanceController.text.trim(),
        phone: targetPhone,
        message: testMsg,
        provider: _waProvider,
      );

      if (mounted) {
        setState(() => _isTestingWa = false);
        if (res['success'] == true) {
          if (_waMode != 'api') {
            setState(() => _waMode = 'api');
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 4),
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'تم الاتصال بنجاح وإرسال رسالة الاختبار! ✅ اضغط "حفظ التغييرات" بالأسفل')),
                ],
              ),
            ),
          );
        } else {
          showDialog(
            context: context,
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.red.shade700),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('فشل إرسال رسالة التجربة',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      res['error'] ?? 'تعذر إتمام الإرسال عبر السيرفر.',
                      style: const TextStyle(
                          color: Color(0xFFFCA5A5), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0x33FFFFFF)),
                    const SizedBox(height: 8),
                    Text(
                      isWhatsPro
                          ? 'نصائح لحل مشكلة الربط مع Whats-Pro:\n'
                              '1. رابط الـ Endpoint: الرابط الصحيح للإرسال هو:\n'
                              'https://whats-pro.net/backend/public/index.php/api/messages/send\n\n'
                              '2. معرف النسخة (Instance ID): غير مطلوب نهائياً في Whats-Pro، اتركه فارغاً.\n\n'
                              '3. رمز التوثيق (Token): تأكد من نسخه بدقة، وتأكد أن حسابك في Whats-Pro نشط وبه باقة رسائل والواتساب متصل بالـ QR.\n\n'
                              '4. رقم هاتف التجربة: تأكد من كتابة كود الدولة بدون أصفار زائدة (مثال: 2010xxxxxxxx).'
                          : 'نصائح للحل:\n'
                              '• تأكد من صحة رابط الـ Endpoint والمسار كاملاً.\n'
                              '• تأكد من كتابة رمز الـ Token أو الـ API Key بدقة.\n'
                              '• تأكد من كتابة معرف النسخة (Instance ID) إذا كان مزودك يتطلبه.\n'
                              '• تأكد من كود الدولة في رقم الهاتف (مثال: 2010xxxxxxxx).\n'
                              '• إذا كنت تستخدم UltraMsg، تأكد أن نسختك متصلة برقم الواتساب (Scan QR).',
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('حسناً',
                        style: TextStyle(color: Color(0xFF38BDF8))),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTestingWa = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            content: Text('خطأ أثناء الاختبار: $e'),
          ),
        );
      }
    }
  }

  // ==========================================================================
  // TAB 5: EXCEL IMPORT & EXPORT MANAGEMENT (إدارة واستيراد وتصدير Excel)
  // ==========================================================================
  Widget _buildExcelManagementTab(bool isDark, Color primaryColor) {
    return Stack(
      children: [
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Hero Banner
              _buildExcelHeroBanner(isDark),
              const SizedBox(height: 18),

              // 2. Import Data from Phone Section
              _buildExcelImportSection(isDark, primaryColor),
              const SizedBox(height: 18),

              // 3. Export Blank Templates Section
              _buildExcelTemplatesSection(isDark, primaryColor),
              const SizedBox(height: 18),

              // 4. Live Data Export Section
              _buildExcelLiveExportSection(isDark, primaryColor),
              const SizedBox(height: 18),

              // 5. Columns Guide Section
              _buildExcelColumnsGuideSection(isDark),
              const SizedBox(height: 24),
            ],
          ),
        ),

        // Processing Overlay
        if (_isExcelProcessing)
          Container(
            color: Colors.black.withValues(alpha: 0.65),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: const Color(0xFF10B981), width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Color(0x3310B981), blurRadius: 20),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                      strokeWidth: 3.5,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'جاري معالجة واستيراد ملف Excel...',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'يتم فحص الأعمدة وحفظ البيانات في قاعدة البيانات بأمان',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Excel Hero Banner
  // --------------------------------------------------------------------------
  Widget _buildExcelHeroBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF064E3B), const Color(0xFF0F172A)]
              : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0x4010B981) : const Color(0xFFA7F3D0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF10B981), width: 1.5),
            ),
            child: const Icon(
              Icons.table_chart_rounded,
              color: Color(0xFF10B981),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'مركز بيانات Excel الشامل',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xFF064E3B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '.xlsx',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'استيراد كشوف الطلاب والمجموعات بنقرة واحدة من ذاكرة الهاتف، وتصدير نماذج فارغة جاهزة للتعبئة أو نسخ بياناتك الحالية.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Section 1: Import From Phone
  // --------------------------------------------------------------------------
  Widget _buildExcelImportSection(bool isDark, Color primaryColor) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'استيراد البيانات من ملفات الهاتف',
      icon: Icons.file_upload_rounded,
      iconColor: const Color(0xFF10B981),
      children: [
        Text(
          'اختر ملف Excel (.xlsx أو .xls) أو CSV من هاتفك وسيقوم النظام بالتعرف الذكي على الأعمدة وحفظ السجلات فورياً:',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),

        // Import Students Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131F33) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF223654) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.school_rounded,
                        color: Color(0xFF38BDF8), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'استيراد كشف الطلاب',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color:
                                isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'الأسماء، أرقام الهواتف، أولياء الأمور، الصفوف، والمجموعات',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Auto create groups switch
              Row(
                children: [
                  Switch.adaptive(
                    value: _autoCreateGroupsOnStudentImport,
                    activeThumbColor: const Color(0xFF10B981),
                    onChanged: (v) {
                      setState(() => _autoCreateGroupsOnStudentImport = v);
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'إنشاء المجموعات الجديدة غير الموجودة تلقائياً وربط الطلاب بها',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Button: Import Students
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  onPressed:
                      _isExcelProcessing ? null : _importStudentsFromExcel,
                  icon: const Icon(Icons.file_open_rounded, size: 18),
                  label: const Text(
                    'اختيار ملف Excel للطلاب واستيراد',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Import Groups Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131F33) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF223654) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF818CF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.groups_rounded,
                        color: Color(0xFF818CF8), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'استيراد كشف المجموعات والفصول',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color:
                                isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'أسماء المجموعات، المواعيد، الاشتراك الشهري، القاعات، والسعة',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Button: Import Groups
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  onPressed: _isExcelProcessing ? null : _importGroupsFromExcel,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text(
                    'اختيار ملف Excel للمجموعات واستيراد',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Subcard 3: Curriculum Lessons
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131F33) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF223654) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        color: Color(0xFF0D9488), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'استيراد خطة المناهج والدروس',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color:
                                isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'المادة، الصف الدراسي، الوحدة/الباب، عنوان الدرس، وترتيب الدروس',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Button: Import Curriculum
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  onPressed:
                      _isExcelProcessing ? null : _importCurriculumFromExcel,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text(
                    'اختيار ملف Excel للمناهج واستيراد',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Section 2: Export Blank Templates
  // --------------------------------------------------------------------------
  Widget _buildExcelTemplatesSection(bool isDark, Color primaryColor) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'تصدير نماذج فارغة جاهزة للتعبئة',
      icon: Icons.download_rounded,
      iconColor: const Color(0xFF38BDF8),
      children: [
        Text(
          'حمّل نماذج Excel الفارغة والمنسقة مع أمثلة توضيحية لملء بياناتك على الهاتف أو الكمبيوتر وإعادة استيرادها:',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),

        // Blank Students Template
        _buildTemplateExportTile(
          title: 'نموذج جهات اتصال الطلاب (.xlsx)',
          subtitle:
              'مطابق لنسخة الكمبيوتر: م، اسم الطالب، هاتف الطالب، اسم ولي الأمر، هاتف ولي الأمر، المجموعة الدراسية، المرحلة',
          badgeText: 'جاهز للتعبئة',
          icon: Icons.assignment_ind_rounded,
          color: const Color(0xFF0D9488),
          isDark: isDark,
          onTap: _exportBlankStudentsTemplate,
        ),

        const SizedBox(height: 10),

        // Blank Groups Template
        _buildTemplateExportTile(
          title: 'نموذج كشف المجموعات (.xlsx)',
          subtitle:
              'مطابق لنسخة الكمبيوتر (15 عمود): اسم المجموعة، المادة، المرحلة، الصف، المكان، اسم المكان، الأيام، المواعيد، الأسعار، السعة، اللون',
          badgeText: 'جاهز للتعبئة',
          icon: Icons.meeting_room_rounded,
          color: const Color(0xFF107C41),
          isDark: isDark,
          onTap: _exportBlankGroupsTemplate,
        ),

        const SizedBox(height: 10),

        // Blank Curriculum Template
        _buildTemplateExportTile(
          title: 'نموذج المنهج الدراسي الفارغ (.xlsx)',
          subtitle:
              'يحتوي على ترويسات: المادة، الصف الدراسي، الوحدة / الباب، عنوان الدرس، رقم الدرس، الأهداف',
          badgeText: 'جاهز للتعبئة',
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF2563EB),
          isDark: isDark,
          onTap: _exportBlankCurriculumTemplate,
        ),
      ],
    );
  }

  Widget _buildTemplateExportTile({
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131F33) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF223654) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color:
                              isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.share_rounded, size: 20),
            tooltip: 'مشاركة وتصدير النموذج',
            style: IconButton.styleFrom(
              backgroundColor: color.withValues(alpha: 0.12),
              foregroundColor: color,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Section 3: Export Live Data to Excel
  // --------------------------------------------------------------------------
  Widget _buildExcelLiveExportSection(bool isDark, Color primaryColor) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'تصدير السجلات الحالية من البرنامج',
      icon: Icons.ios_share_rounded,
      iconColor: const Color(0xFFF59E0B),
      children: [
        Text(
          'تصدير كشوف بياناتك الحالية المسجلة في التطبيق إلى ملفات Excel منسقة للطباعة أو الأرشفة:',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportLiveStudentsToExcel,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text(
                  'تصدير كل الطلاب',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D9488),
                  side: const BorderSide(color: Color(0xFF0D9488), width: 1.2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportLiveGroupsToExcel,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text(
                  'تصدير كل المجموعات',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF107C41),
                  side: const BorderSide(color: Color(0xFF107C41), width: 1.2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _exportLiveCurriculumToExcel,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text(
              'تصدير كل المناهج والدروس المسجلة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFF2563EB), width: 1.2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Section 4: Columns Guide
  // --------------------------------------------------------------------------
  Widget _buildExcelColumnsGuideSection(bool isDark) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'دليل ترويسات الأعمدة المدعومة',
      icon: Icons.help_outline_rounded,
      iconColor: const Color(0xFF818CF8),
      children: [
        Text(
          'محرك الاستيراد ذكي ومرن يتعرف تلقائياً على الأعمدة بأي من الأسماء التالية (عربي أو إنجليزي):',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        _buildGuideRow(
          field: 'اسم الطالب',
          names: 'اسم الطالب، الاسم بالكامل، الاسم، Name، Student',
          isDark: isDark,
        ),
        _buildGuideRow(
          field: 'هاتف الطالب',
          names: 'هاتف الطالب، موبايل، رقم الطالب، Phone، Mobile',
          isDark: isDark,
        ),
        _buildGuideRow(
          field: 'هاتف ولي الأمر',
          names: 'هاتف ولي الأمر، موبايل ولي الأمر، Parent Phone',
          isDark: isDark,
        ),
        _buildGuideRow(
          field: 'المجموعة',
          names: 'اسم المجموعة، المجموعة، الفصل، Group، Batch',
          isDark: isDark,
        ),
        _buildGuideRow(
          field: 'الصف الدراسي',
          names: 'الصف الدراسي، الصف، السنة الدراسية، Grade',
          isDark: isDark,
        ),
        _buildGuideRow(
          field: 'الاشتراك / الدين',
          names: 'الاشتراك الشهري، المبلغ المتبقي، الدين، Price',
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildGuideRow({
    required String field,
    required String names,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              field,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10B981),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              names,
              style: TextStyle(
                fontSize: 11,
                color:
                    isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // EXCEL ACTION HANDLERS
  // --------------------------------------------------------------------------
  Future<void> _importStudentsFromExcel() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (files.isEmpty || files.first.path == null) return;
      final filePath = files.first.path!;
      final bytes = await File(filePath).readAsBytes();

      setState(() => _isExcelProcessing = true);

      final report = await ExcelImportService.importStudents(
        bytes: bytes,
        database: widget.database,
        autoCreateGroups: _autoCreateGroupsOnStudentImport,
      );

      setState(() => _isExcelProcessing = false);

      if (mounted) {
        _showImportReportDialog(report);
        widget.onNavConfigChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExcelProcessing = false);
        _showErrorSnackBar('حدث خطأ أثناء استيراد الطلاب: $e');
      }
    }
  }

  Future<void> _importGroupsFromExcel() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (files.isEmpty || files.first.path == null) return;
      final filePath = files.first.path!;
      final bytes = await File(filePath).readAsBytes();

      setState(() => _isExcelProcessing = true);

      final report = await ExcelImportService.importGroups(
        bytes: bytes,
        database: widget.database,
      );

      setState(() => _isExcelProcessing = false);

      if (mounted) {
        _showImportReportDialog(report);
        widget.onNavConfigChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExcelProcessing = false);
        _showErrorSnackBar('حدث خطأ أثناء استيراد المجموعات: $e');
      }
    }
  }

  Future<void> _exportBlankStudentsTemplate() async {
    try {
      final bytes = ExcelImportService.createStudentsTemplateBytes();
      await _shareExcelBytes(
        fileName: 'نموذج_جهات_اتصال_الطلاب.xlsx',
        bytes: bytes,
        subject: 'نموذج جهات اتصال الطلاب للتعبئة - Edu Academy',
      );
    } catch (e) {
      _showErrorSnackBar('فشل تصدير النموذج: $e');
    }
  }

  Future<void> _exportBlankGroupsTemplate() async {
    try {
      final bytes = ExcelImportService.createGroupsTemplateBytes();
      await _shareExcelBytes(
        fileName: 'نموذج_المجموعات.xlsx',
        bytes: bytes,
        subject: 'نموذج المجموعات للتعبئة - Edu Academy',
      );
    } catch (e) {
      _showErrorSnackBar('فشل تصدير النموذج: $e');
    }
  }

  Future<void> _exportLiveStudentsToExcel() async {
    try {
      setState(() => _isExcelProcessing = true);
      final students = await widget.database.getStudents();
      final groups = await widget.database.getGroups();
      final Map<String, String> groupNames = {
        for (final g in groups) g.id: g.name
      };

      if (students.isEmpty) {
        setState(() => _isExcelProcessing = false);
        _showErrorSnackBar('لا يوجد طلاب مسجلين حالياً للتصدير');
        return;
      }

      final bytes = ExcelImportService.exportStudentsToExcelBytes(
        students: students,
        groupNames: groupNames,
      );

      setState(() => _isExcelProcessing = false);

      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      await _shareExcelBytes(
        fileName: 'جهات_اتصال_الطلاب_$dateStr.xlsx',
        bytes: bytes,
        subject: 'جهات اتصال الطلاب ($dateStr) - Edu Academy',
      );
    } catch (e) {
      setState(() => _isExcelProcessing = false);
      _showErrorSnackBar('فشل تصدير بيانات الطلاب: $e');
    }
  }

  Future<void> _exportLiveGroupsToExcel() async {
    try {
      setState(() => _isExcelProcessing = true);
      final groups = await widget.database.getGroups();
      final students = await widget.database.getStudents();

      if (groups.isEmpty) {
        setState(() => _isExcelProcessing = false);
        _showErrorSnackBar('لا توجد مجموعات مسجلة حالياً للتصدير');
        return;
      }

      final Map<String, int> counts = {};
      for (final s in students) {
        if (s.groupId != null) {
          counts[s.groupId!] = (counts[s.groupId!] ?? 0) + 1;
        }
      }

      final bytes = ExcelImportService.exportGroupsToExcelBytes(
        groups: groups,
        studentCounts: counts,
      );

      setState(() => _isExcelProcessing = false);

      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      await _shareExcelBytes(
        fileName: 'المجموعات_$dateStr.xlsx',
        bytes: bytes,
        subject: 'سجل المجموعات ($dateStr) - Edu Academy',
      );
    } catch (e) {
      setState(() => _isExcelProcessing = false);
      _showErrorSnackBar('فشل تصدير بيانات المجموعات: $e');
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

      setState(() => _isExcelProcessing = true);

      int totalSaved = 0;
      int totalUnits = 0;
      int successfulFiles = 0;

      for (final f in validFiles) {
        final filePath = f.path!;
        final fileName = p.basename(filePath);
        final file = File(filePath);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();

        final report = await CurriculumExcelService.importCurriculum(
          bytes: bytes,
          fileName: fileName,
          database: widget.database,
        );

        if (report.totalSaved > 0) {
          totalSaved += report.totalSaved;
          totalUnits += report.unitsCount;
          successfulFiles++;
        }
      }

      setState(() => _isExcelProcessing = false);

      if (mounted) {
        if (totalSaved == 0) {
          _showErrorSnackBar(
              'لم يتم العثور على دروس صالحة للاستيراد في الملفات المختارة');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text(validFiles.length > 1
                  ? 'تم استيراد $totalSaved درساً بنجاح من $successfulFiles ملفات مناهج في $totalUnits وحدة دراسية ✅'
                  : 'تم استيراد $totalSaved درساً بنجاح في $totalUnits وحدة دراسية ✅'),
            ),
          );
          widget.onNavConfigChanged?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExcelProcessing = false);
        _showErrorSnackBar('حدث خطأ أثناء استيراد المنهج: $e');
      }
    }
  }

  Future<void> _exportBlankCurriculumTemplate() async {
    try {
      final bytes = CurriculumExcelService.createBlankCurriculumTemplateBytes();
      await _shareExcelBytes(
        fileName: 'نموذج_المنهج_الدراسي_فارغ_EduAcademy.xlsx',
        bytes: bytes,
        subject: 'نموذج المنهج الدراسي للتعبئة - Edu Academy',
      );
    } catch (e) {
      _showErrorSnackBar('فشل تصدير النموذج: $e');
    }
  }

  Future<void> _exportLiveCurriculumToExcel() async {
    try {
      setState(() => _isExcelProcessing = true);
      final lessons = await widget.database.getCurriculumLessons();

      if (lessons.isEmpty) {
        setState(() => _isExcelProcessing = false);
        _showErrorSnackBar('لا توجد مناهج أو دروس مسجلة حالياً للتصدير');
        return;
      }

      final bytes = CurriculumExcelService.exportCurriculum(lessons);

      setState(() => _isExcelProcessing = false);

      await _shareExcelBytes(
        fileName: 'سجل_المناهج_الدراسية_الفعلي_EduAcademy.xlsx',
        bytes: bytes,
        subject: 'سجل المناهج والدروس الفعلي - Edu Academy',
      );
    } catch (e) {
      setState(() => _isExcelProcessing = false);
      _showErrorSnackBar('فشل تصدير المناهج: $e');
    }
  }

  Future<void> _shareExcelBytes({
    required String fileName,
    required Uint8List bytes,
    required String subject,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: fileName)
        ],
        subject: subject,
        text: subject,
      ),
    );
  }

  void _showImportReportDialog(ExcelImportReport report) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: report.isSuccess
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : Colors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  report.isSuccess
                      ? Icons.check_circle_rounded
                      : Icons.info_rounded,
                  color:
                      report.isSuccess ? const Color(0xFF10B981) : Colors.amber,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  report.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Metric summary chips
              Row(
                children: [
                  Expanded(
                    child: _buildReportMetricChip(
                      label: 'تم بنجاح',
                      value: '${report.successCount}',
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildReportMetricChip(
                      label: 'إجمالي الصفوف',
                      value: '${report.totalRows}',
                      color: const Color(0xFF38BDF8),
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              if (report.createdGroups.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'المجموعات الجديدة التي تم إنشاؤها تلقائياً (${report.createdGroups.length}):',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: report.createdGroups.map((g) {
                    return Chip(
                      label: Text(g, style: const TextStyle(fontSize: 10.5)),
                      backgroundColor:
                          const Color(0xFF10B981).withValues(alpha: 0.15),
                      labelPadding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                ),
              ],
              if (report.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...report.notes.map((n) => Text(
                      '• $n',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF475569),
                      ),
                    )),
              ],
              if (report.errors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'تنبيهات وأخطاء:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.red.shade400),
                ),
                ...report.errors.map((e) => Text(
                      '• $e',
                      style:
                          TextStyle(fontSize: 11, color: Colors.red.shade300),
                    )),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportMetricChip({
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        content: Text(msg),
      ),
    );
  }

  // ==========================================================================
  // TAB 5: SECURITY, BACKUP & PROTECTION (الحماية والنسخ الاحتياطي والأمان)
  // ==========================================================================
  Widget _buildSecurityManagementTab(bool isDark, Color primaryColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          _buildSecurityHeroBanner(isDark),
          const SizedBox(height: 18),

          // 0. Student App & Student Data Security Card (قسم بيانات وتأمين تطبيق الطالب)
          _buildStudentDataAndAppControlCard(isDark, primaryColor),
          const SizedBox(height: 18),

          // 1. App Lock & Biometrics (قفل التطبيق والبصمة)
          _buildAppLockCard(isDark),
          const SizedBox(height: 18),

          // 2. Google Drive / Cloud Backup (النسخ السحابي لجوجل درايف بدون متطلبات)
          _buildGoogleDriveBackupCard(isDark),
          const SizedBox(height: 18),

          // 3. Local Phone Backup & Restore (النسخ المحلي واستعادة البيانات)
          _buildLocalBackupCard(isDark),
          const SizedBox(height: 18),

          // 4. Factory Reset (إعادة ضبط المصنع وتصفير البيانات)
          _buildFactoryResetCard(isDark),
        ],
      ),
    );
  }

  Widget _buildSecurityHeroBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
              : [const Color(0xFFEEF2FF), const Color(0xFFF8FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0x666366F1) : const Color(0xFFC7D2FE),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF6366F1).withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.security_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مركز الحماية والنسخ الاحتياطي والأمان',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                SizedBox(height: 3),
                Text(
                  'قفل التطبيق بكلمة المرور والبصمة، النسخ الاحتياطي السحابي لجوجل درايف، وإعادة ضبط المصنع.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentDataAndAppControlCard(bool isDark, Color primaryColor) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'قسم بيانات وتأمين تطبيق الطالب',
      icon: Icons.phonelink_lock_rounded,
      iconColor: const Color(0xFF00F2FE),
      children: [
        Text(
          'التحكم الكامل في حسابات دخول الطلاب لتطبيق الطالب، إدارة الرموز السرية PIN، تفعيل المصادقة الثنائية 2FA عبر واتساب، وترقية الأكواد لـ 5 أرقام.',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),

        // Live Cloud Metrics Stream
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('academies')
              .doc('default')
              .collection('students')
              .snapshots(),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            final total = docs.length;
            final withCustomPin = docs.where((d) => d.data()['pin_code'] != null && d.data()['pin_code'].toString().isNotEmpty).length;
            final with2Fa = docs.where((d) => d.data()['require_2fa'] != false).length;

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00F2FE),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'حسابات بالسحابة',
                          style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 32, color: Colors.grey.withValues(alpha: 0.3)),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '$withCustomPin',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'رمز PIN مفعل',
                          style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 32, color: Colors.grey.withValues(alpha: 0.3)),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '$with2Fa',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'تأمين 2FA نشط',
                          style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),

        // Main CTA Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F2FE),
              foregroundColor: const Color(0xFF050B14),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: const Icon(Icons.phonelink_lock_rounded, size: 20),
            label: const Text(
              'فتح لوحة تحكم وتأمين بيانات تطبيق الطالب ➔',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeacherStudentAppControlScreen(database: widget.database),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // Secondary Actions Row (5 Digits Upgrade & Cloud Sync)
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.casino_rounded, size: 16, color: Color(0xFF8B5CF6)),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'أكواد عشوائية (5 أرقام) 🎲',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                  ),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Row(
                        children: [
                          Icon(Icons.casino_rounded, color: Color(0xFF8B5CF6)),
                          SizedBox(width: 8),
                          Text('توليد أكواد عشوائية (5 أرقام) 🎲', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      content: const Text(
                        'سيتم تعيين أكواد عشوائية فريدة وغير مسلسلة مكونة من 5 أرقام (مثال: 48291, 71053) لجميع الطلاب.\nسيتم تحديث سجلات الحضور والامتحانات والمصروفات ومزامنة السحابة تلقائياً دون أي فقد للبيانات.\n\nهل ترغب في البدء؟',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('بدء التوليد 🎲'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    try {
                      final count = await widget.database.renumberAllStudentsTo5Digits();
                      await CloudSyncService.instance.syncStudents();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم تعيين أكواد عشوائية فريدة لـ $count طالباً ومزامنة السحابة بنجاح 🎲'),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('خطأ أثناء الترقية: $e'), backgroundColor: const Color(0xFFEF4444)),
                        );
                      }
                    }
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.cloud_sync_rounded, size: 16, color: Color(0xFF10B981)),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'مزامنة الطلاب سحابياً ☁️',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                  ),
                ),
                onPressed: () async {
                  try {
                    await CloudSyncService.instance.syncStudents();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تمت مزامنة بيانات الطلاب مع السحابة بنجاح ☁️'),
                          backgroundColor: Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ في المزامنة: $e'), backgroundColor: const Color(0xFFEF4444)),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppLockCard(bool isDark) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'قفل التطبيق والأمان البيومتري',
      icon: Icons.lock_person_rounded,
      iconColor: const Color(0xFF6366F1),
      children: [
        // App Lock switch
        Material(
          color: Colors.transparent,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'تفعيل قفل التطبيق',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            subtitle: Text(
              'يطلب رمز PIN أو البصمة عند فتح التطبيق أو العودة إليه من الخلفية',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B)),
            ),
            value: _appLockEnabled,
            activeThumbColor: const Color(0xFF6366F1),
            onChanged: _toggleAppLock,
          ),
        ),
        const Divider(height: 16),

        // Biometrics switch
        Material(
          color: Colors.transparent,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                const Text(
                  'المصادقة ببصمة الإصبع / الوجه',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                if (!_isBiometricsSupported) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('غير مدعوم بالجهاز',
                        style: TextStyle(fontSize: 10, color: Colors.orange)),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              'السماح بفتح التطبيق وتأكيد العمليات ببصمة الإصبع بدلاً من كتابة الـ PIN',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B)),
            ),
            value: _biometricsEnabled,
            activeThumbColor: const Color(0xFF10B981),
            onChanged: _isBiometricsSupported ? _toggleBiometrics : null,
          ),
        ),
        const Divider(height: 16),

        // Sensitive actions auth switch
        Material(
          color: Colors.transparent,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'حماية العمليات الحساسة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            subtitle: Text(
              'المطالبة بالتحقق الأمني قبل استعادة النسخ الاحتياطية أو تصفير وضبط المصنع',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B)),
            ),
            value: _requireAuthForSensitive,
            activeThumbColor: const Color(0xFFF59E0B),
            onChanged: _toggleRequireAuth,
          ),
        ),
        const SizedBox(height: 12),

        // Change PIN Button
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6366F1),
              side: const BorderSide(color: Color(0xFF6366F1), width: 1.2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              backgroundColor: const Color(0xFF6366F1)
                  .withValues(alpha: isDark ? 0.08 : 0.05),
            ),
            onPressed: _changePin,
            icon: const Icon(Icons.password_rounded, size: 20),
            label: Text(
              _currentPin.isEmpty
                  ? 'تعيين رمز مرور PIN للتطبيق'
                  : 'تغيير رمز المرور (PIN الحالي: ****)',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleDriveBackupCard(bool isDark) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'رابط Google Apps Script Webhook',
      icon: Icons.cloud_sync_rounded,
      iconColor: const Color(0xFF38BDF8),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _isWebhookConnected
              ? const Color(0xFF10B981).withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isWebhookConnected ? const Color(0xFF10B981) : Colors.grey,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isWebhookConnected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color:
                  _isWebhookConnected ? const Color(0xFF10B981) : Colors.grey,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              _isWebhookConnected ? 'متصل' : 'غير متصل',
              style: TextStyle(
                color:
                    _isWebhookConnected ? const Color(0xFF10B981) : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      children: [
        // Subtitle & Email Info
        Row(
          children: [
            Expanded(
              child: Text(
                'يربط التطبيق بمجلد Google Drive الخاص بك تلقائياً بدون تعقيدات OAuth أو قيود النطاق.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
            if (_connectedUserEmail.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                ),
                child: Text(
                  'الحساب: $_connectedUserEmail',
                  style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF818CF8),
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Webhook URL input field
        TextFormField(
          controller: _webhookUrlCtrl,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'https://script.google.com/macros/s/.../exec',
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 11),
            prefixIcon: const Icon(Icons.link_rounded,
                color: Color(0xFF38BDF8), size: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_webhookUrlCtrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _webhookUrlCtrl.clear();
                      setState(() => _isWebhookConnected = false);
                      widget.database.setSetting('google_webhook_url', '');
                    },
                  ),
                IconButton(
                  tooltip: 'لصق من الحافظة',
                  icon: const Icon(Icons.paste_rounded,
                      size: 18, color: Color(0xFF38BDF8)),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _webhookUrlCtrl.text = data!.text!.trim();
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
            filled: true,
            fillColor:
                isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: _isWebhookConnected
                    ? const Color(0xFF10B981).withValues(alpha: 0.5)
                    : (isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1)),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),

        // Action Buttons Row: [ فحص وحفظ الرابط ] and [ أخذ نسخة سحابية على Drive الآن ]
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  elevation: 1,
                ),
                onPressed: _isTestingWebhook ? null : _testAndSaveWebhookUrl,
                icon: _isTestingWebhook
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.bolt_rounded, size: 18),
                label: Text(
                  _isTestingWebhook ? 'جاري الفحص...' : 'فحص وحفظ الرابط ⚡',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  elevation: 1,
                ),
                onPressed:
                    _isUploadingCloudBackup ? null : _performCloudBackupNow,
                icon: _isUploadingCloudBackup
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(
                  _isUploadingCloudBackup
                      ? 'جاري الرفع...'
                      : 'أخذ نسخة سحابية الآن ☁️',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Safe storage banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                const Color(0xFF10B981).withValues(alpha: isDark ? 0.1 : 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.25)),
          ),
          child: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'يتم حفظ وتشفير النسخ الاحتياطية مباشرة داخل مجلد "نسخ_منظومة_الأستاذ_الاحتياطية" بحسابك.',
                  style: TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // --- SCHEDULED AUTOMATIC CLOUD BACKUP SECTION (النسخ المجدول بمواعيد ثابتة) ---
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color:
                    isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.alarm_on_rounded,
                        color: Color(0xFF8B5CF6), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'النسخ السحابي التلقائي المجدول (بدون تدخل مني)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'رفع نسخة سحابية يومياً في موعد ثابت بدون الحاجة للضغط على أي زر.',
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _autoCloudBackupEnabled,
                    activeThumbColor: const Color(0xFF8B5CF6),
                    onChanged: _toggleAutoCloudBackup,
                  ),
                ],
              ),
              if (_autoCloudBackupEnabled) ...[
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'موعد النسخ اليومي الثابت:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    InkWell(
                      onTap: _pickAutoCloudBackupTime,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF8B5CF6)
                                  .withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule_rounded,
                                size: 15, color: Color(0xFF8B5CF6)),
                            const SizedBox(width: 6),
                            Text(
                              _autoCloudBackupTime,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF8B5CF6)),
                            ),
                            const SizedBox(width: 4),
                            const Text('✏️', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _lastAutoCloudBackupDate.isNotEmpty
                      ? '✅ آخر نسخة تلقائية تم رفعها: $_lastAutoCloudBackupDate'
                      : '⏳ سيتم أخذ أول نسخة تلقائية اليوم عند موعد: $_autoCloudBackupTime',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w500),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // --- EXPANDABLE GUIDE FOR GOOGLE APPS SCRIPT ---
        InkWell(
          onTap: () => setState(() => _showWebhookGuide = !_showWebhookGuide),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131D31) : const Color(0xFFEEF2F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.help_outline_rounded,
                    color: Color(0xFF38BDF8), size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'دليل تجهيز وتفعيل Google Webhook مجاناً (دقيقتين فقط وبدون أي قيود)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFF38BDF8)),
                  ),
                ),
                Icon(
                  _showWebhookGuide
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF38BDF8),
                ),
              ],
            ),
          ),
        ),

        if (_showWebhookGuide) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    '1. ادخل إلى منصة سكريبت جوجل: script.google.com ثم اضغط على مشروع جديد (New project).',
                    style: TextStyle(fontSize: 11.5, height: 1.5)),
                const SizedBox(height: 6),
                const Text(
                    '2. امسح الكود الافتراضي بالكامل، ثم اضغط الزر بالأسفل لنسخ الكود الجاهز، والصقه في المحرر ثم اضغط حفظ (Ctrl + S).',
                    style: TextStyle(fontSize: 11.5, height: 1.5)),
                const SizedBox(height: 6),
                const Text(
                    '3. اضغط الزر الأزرق في الأعلى: Deploy (نشر) ثم اختر New deployment (نشر جديد).',
                    style: TextStyle(fontSize: 11.5, height: 1.5)),
                const SizedBox(height: 6),
                const Text(
                    '4. بجوار Select type اضغط علامة الترس ⚙ واختر Web app.',
                    style: TextStyle(fontSize: 11.5, height: 1.5)),
                const SizedBox(height: 6),
                const Text('5. اضبط الخيارات كالتالي:',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: Text(
                      '• Execute as: Me (حسابك)\n• Who has access: Anyone (أي شخص يملك الرابط - لضمان وصول تطبيقك إليه)',
                      style: TextStyle(
                          fontSize: 11, height: 1.5, color: Color(0xFF38BDF8))),
                ),
                const SizedBox(height: 6),
                const Text(
                    '6. اضغط Deploy وامنح الإذن لحسابك (Authorize Access)، ثم انسخ Web app URL والصقه في الحقل أعلاه واضغط "فحص وحفظ الرابط".',
                    style: TextStyle(fontSize: 11.5, height: 1.5)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    onPressed: _copyScriptCode,
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: const Text('نسخ كود Google Apps Script الجاهز',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),

        // --- CLOUD BACKUPS LIST IN GOOGLE DRIVE ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_done_rounded,
                    color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 8),
                Text(
                  'النسخ السحابية المتوفرة على Drive (${_cloudBackupsList.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            IconButton(
              icon: _isFetchingCloudBackups
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF38BDF8)))
                  : const Icon(Icons.refresh_rounded,
                      size: 18, color: Color(0xFF38BDF8)),
              tooltip: 'تحديث قائمة النسخ',
              onPressed:
                  _isFetchingCloudBackups ? null : _fetchCloudBackupsList,
            ),
          ],
        ),
        const SizedBox(height: 6),

        if (_isRestoringCloudBackup) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: const Row(
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF10B981))),
                SizedBox(width: 10),
                Text('جاري تنزيل واستعادة النسخة السحابية من Drive...',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        if (_cloudBackupsList.isEmpty && !_isFetchingCloudBackups)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _isWebhookConnected
                    ? 'لم يتم العثور على نسخ سابقة في Drive بعد. اضغط "أخذ نسخة سحابية الآن" لحفظ أول نسخة!'
                    : 'قم بضبط وفحص رابط Webhook أعلاه لعرض النسخ السحابية المحفوظة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          )
        else
          Column(
            children: _cloudBackupsList.map((file) {
              final sizeKb = file.size != null
                  ? '${(int.tryParse(file.size!) ?? 0) ~/ 1024} KB'
                  : '';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_rounded,
                        color: Color(0xFF38BDF8), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${file.createdTime.split('T').first} ${sizeKb.isNotEmpty ? '• $sizeKb' : ''}',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: isDark
                                    ? Colors.grey
                                    : Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded,
                          color: Color(0xFF10B981), size: 20),
                      tooltip: 'استعادة على الهاتف',
                      onPressed: _isRestoringCloudBackup
                          ? null
                          : () => _restoreCloudBackup(file),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent, size: 20),
                      tooltip: 'حذف من Drive',
                      onPressed: () => _deleteCloudBackup(file),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildLocalBackupCard(bool isDark) {
    return _buildCardWrapper(
      isDark: isDark,
      title: 'النسخ المحلي واستعادة البيانات',
      icon: Icons.folder_zip_rounded,
      iconColor: const Color(0xFF10B981),
      children: [
        Text(
          'يمكنك تصدير قاعدة البيانات كاملة لملف محفوظ على هاتفك في مجلد التحميلات (Downloads)، أو استعادة نسخة سابقة في أي وقت:',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            // Export / Backup button
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isBackingUp ? null : _performLocalBackup,
                  icon: _isBackingUp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_rounded, size: 20),
                  label: const Text(
                    'أخذ نسخة للجهاز',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Import / Restore button
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side:
                        const BorderSide(color: Color(0xFF10B981), width: 1.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    backgroundColor: const Color(0xFF10B981)
                        .withValues(alpha: isDark ? 0.08 : 0.05),
                  ),
                  onPressed: _isRestoring ? null : _performRestore,
                  icon: _isRestoring
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF10B981)),
                        )
                      : const Icon(Icons.settings_backup_restore_rounded,
                          size: 20),
                  label: const Text(
                    'استعادة نسخة (.db)',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // PC App JSON Package Row
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                const Color(0xFF6366F1).withValues(alpha: isDark ? 0.08 : 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.laptop_mac_rounded,
                      color: Color(0xFF818CF8), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'مزامنة حزمة منظومة الكمبيوتر (my-app JSON)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'تصدير واستيراد نفس ملف الحزمة المستخدم في تطبيق الكمبيوتر لضمان عدم فقدان أي بيانات نهائياً عند التنقل بين الجهازين.',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF818CF8),
                        side: const BorderSide(color: Color(0xFF818CF8)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: _isBackingUp ? null : _performPCJsonExport,
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('تصدير حزمة (.json)',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: _isRestoring ? null : _performPCJsonImport,
                      icon: const Icon(Icons.file_upload_rounded, size: 16),
                      label: const Text('استيراد حزمة (.json)',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFactoryResetCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFEF4444), size: 22),
              SizedBox(width: 8),
              Text(
                'منطقة الخطر - إعادة ضبط المصنع',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'حذف وتصفير جميع بيانات التطبيق نهائياً وقاعدة البيانات بالكامل (الطلاب، المجموعات، الحضور، المدفوعات، الامتحانات، والإعدادات) والرجوع للوضع النظيف الأصلي. يتطلب هذا الإجراء تأكيد الهوية بالبصمة/الرمز.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: _isResetting ? null : _performFactoryReset,
              icon: _isResetting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.delete_forever_rounded, size: 22),
              label: const Text(
                'إعادة ضبط المصنع وتصفير كل البيانات ⚠️',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Security Logic Handlers ---

  Future<void> _toggleAppLock(bool value) async {
    HapticFeedback.selectionClick();
    if (value && _currentPin.isEmpty) {
      final pinSet = await SecurityService.showChangePinDialog(
        context: context,
        database: widget.database,
      );
      if (!pinSet) return;
      final savedPin = await widget.database
          .getSetting('security_pin', defaultValue: '1234');
      setState(() => _currentPin = savedPin);
    }

    await widget.database
        .setSetting('security_app_lock_enabled', value.toString());
    setState(() => _appLockEnabled = value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              value ? const Color(0xFF6366F1) : const Color(0xFF64748B),
          content: Text(value
              ? 'تم تفعيل قفل التطبيق بالأمان بنجاح 🔒'
              : 'تم تعطيل قفل التطبيق'),
        ),
      );
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    HapticFeedback.selectionClick();
    await widget.database
        .setSetting('security_biometrics_enabled', value.toString());
    setState(() => _biometricsEnabled = value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF10B981),
          content: Text(value
              ? 'تم تفعيل المصادقة بالبصمة بنجاح 👆'
              : 'تم تعطيل المصادقة بالبصمة'),
        ),
      );
    }
  }

  Future<void> _toggleRequireAuth(bool value) async {
    HapticFeedback.selectionClick();
    await widget.database.setSetting('security_require_auth', value.toString());
    setState(() => _requireAuthForSensitive = value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFF59E0B),
          content: Text(value
              ? 'تم تفعيل طلب الأمان للعمليات الحساسة 🛡️'
              : 'تم تعطيل تأكيد الأمان للعمليات الحساسة'),
        ),
      );
    }
  }

  Future<void> _changePin() async {
    HapticFeedback.mediumImpact();
    final success = await SecurityService.showChangePinDialog(
      context: context,
      database: widget.database,
    );
    if (success) {
      final newPin = await widget.database
          .getSetting('security_pin', defaultValue: '1234');
      if (mounted) {
        setState(() => _currentPin = newPin);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF10B981),
            content: Text('تم تحديث وحفظ رمز المرور PIN بنجاح ✅'),
          ),
        );
      }
    }
  }

  Future<void> _performLocalBackup() async {
    HapticFeedback.mediumImpact();
    setState(() => _isBackingUp = true);
    try {
      final file = await BackupService.createLocalBackup(widget.database);
      final fileName = p.basename(file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10B981),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'تم إنشاء النسخة بنجاح في الهاتف ومجلد Downloads:\n$fileName'),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('فشل إنشاء النسخة الاحتياطية: $e');
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _performRestore() async {
    HapticFeedback.heavyImpact();
    setState(() => _isRestoring = true);
    try {
      final ok = await BackupService.restoreBackupWithPicker(
        context: context,
        database: widget.database,
      );
      if (ok && mounted) {
        await _loadData();
        widget.onNavConfigChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('فشل استعادة النسخة الاحتياطية: $e');
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _performPCJsonExport() async {
    HapticFeedback.lightImpact();
    setState(() => _isBackingUp = true);
    try {
      await BackupService.sharePCBackupJSON(
        context: context,
        database: widget.database,
      );
    } catch (e) {
      if (mounted) _showErrorSnackBar('فشل تصدير حزمة الكمبيوتر: $e');
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _performPCJsonImport() async {
    HapticFeedback.heavyImpact();
    setState(() => _isRestoring = true);
    try {
      final ok = await BackupService.restorePCBackupWithPicker(
        context: context,
        database: widget.database,
      );
      if (ok && mounted) {
        await _loadData();
        widget.onNavConfigChanged?.call();
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('فشل استيراد حزمة الكمبيوتر: $e');
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _performFactoryReset() async {
    HapticFeedback.heavyImpact();
    setState(() => _isResetting = true);
    try {
      final ok = await BackupService.performFactoryReset(
        context: context,
        database: widget.database,
      );
      if (ok && mounted) {
        await _loadData();
        widget.onNavConfigChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('حدث خطأ أثناء إعادة ضبط المصنع: $e');
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  // --- Google Webhook & Scheduled Cloud Backup Handlers ---

  Future<void> _testAndSaveWebhookUrl() async {
    final url = _webhookUrlCtrl.text.trim();
    if (url.isEmpty) {
      _showErrorSnackBar('يرجى لصق رابط Webhook أولاً');
      return;
    }
    if (!GoogleWebhookService.isValidUrl(url)) {
      _showErrorSnackBar(
          'الرابط غير صالح. يجب أن يبدأ بـ https://script.google.com/macros/s/.../exec');
      return;
    }

    setState(() => _isTestingWebhook = true);
    try {
      final res = await GoogleWebhookService.testConnection(url);
      if (res['success'] == true) {
        await widget.database.setSetting('google_webhook_url', url);
        final email = (res['user'] ?? '').toString();
        if (email.isNotEmpty) {
          await widget.database.setSetting('google_webhook_user_email', email);
        }
        if (mounted) {
          setState(() {
            _isWebhookConnected = true;
            _connectedUserEmail = email;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF10B981),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'تم الاتصال بنجاح بـ Google Drive! ${email.isNotEmpty ? '($email)' : ''}'),
                  ),
                ],
              ),
            ),
          );
          _fetchCloudBackupsList();
        }
      } else {
        if (mounted) {
          setState(() => _isWebhookConnected = false);
          _showErrorSnackBar(res['error']?.toString() ??
              'فشل الاتصال برابط Webhook. تأكد من إعدادات النشر (Anyone).');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isWebhookConnected = false);
        _showErrorSnackBar('حدث خطأ أثناء اختبار الرابط: $e');
      }
    } finally {
      if (mounted) setState(() => _isTestingWebhook = false);
    }
  }

  Future<void> _performCloudBackupNow() async {
    final url = _webhookUrlCtrl.text.trim();
    if (url.isEmpty || !GoogleWebhookService.isValidUrl(url)) {
      _showErrorSnackBar(
          'يرجى فحص وحفظ رابط Webhook أولاً قبل أخذ نسخة سحابية.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isUploadingCloudBackup = true);
    try {
      final res = await GoogleWebhookService.uploadBackup(
        webhookUrl: url,
        database: widget.database,
      );
      final fileName = res.name;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10B981),
            content: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'تم رفع وحفظ النسخة على Google Drive بنجاح!\n$fileName'),
                ),
              ],
            ),
          ),
        );
        _fetchCloudBackupsList();
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('خطأ أثناء الرفع السحابي: $e');
    } finally {
      if (mounted) setState(() => _isUploadingCloudBackup = false);
    }
  }

  Future<void> _fetchCloudBackupsList() async {
    final url = _webhookUrlCtrl.text.trim();
    if (url.isEmpty || !GoogleWebhookService.isValidUrl(url)) return;

    setState(() => _isFetchingCloudBackups = true);
    try {
      final list = await GoogleWebhookService.listBackups(url);
      if (mounted) {
        setState(() {
          _cloudBackupsList = list;
          if (list.isNotEmpty || _isWebhookConnected) {
            _isWebhookConnected = true;
          }
        });
      }
    } catch (_) {
      // silent or keep previous
    } finally {
      if (mounted) setState(() => _isFetchingCloudBackups = false);
    }
  }

  Future<void> _restoreCloudBackup(GoogleDriveWebhookFile file) async {
    final url = _webhookUrlCtrl.text.trim();
    if (url.isEmpty || !GoogleWebhookService.isValidUrl(url)) {
      _showErrorSnackBar('رابط Webhook غير صالح أو غير متصل');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 26),
            SizedBox(width: 10),
            Text('تأكيد الاستعادة السحابية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في استعادة البيانات من النسخة:\n"${file.name}"؟\n\nتنبيه: سيتم استبدال البيانات الحالية بالبيانات الموجودة في هذه النسخة.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة الآن'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    HapticFeedback.heavyImpact();
    setState(() => _isRestoringCloudBackup = true);
    try {
      final count = await GoogleWebhookService.restoreBackup(
        webhookUrl: url,
        fileId: file.id,
        database: widget.database,
      );
      if (count > 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF10B981),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('تمت استعادة $count سجل بنجاح من Google Drive!'),
                ],
              ),
            ),
          );
          await _loadData();
          widget.onNavConfigChanged?.call();
        }
      } else {
        if (mounted) _showErrorSnackBar('فشلت عملية استعادة النسخة السحابية.');
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('حدث خطأ أثناء الاستعادة السحابية: $e');
    } finally {
      if (mounted) setState(() => _isRestoringCloudBackup = false);
    }
  }

  Future<void> _deleteCloudBackup(GoogleDriveWebhookFile file) async {
    final url = _webhookUrlCtrl.text.trim();
    if (url.isEmpty || !GoogleWebhookService.isValidUrl(url)) {
      _showErrorSnackBar('رابط Webhook غير صالح');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف النسخة من Drive',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'هل تريد بالتأكيد حذف ملف النسخة الاحتياطية:\n"${file.name}" من حسابك في Google Drive؟',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final ok = await GoogleWebhookService.deleteBackup(
        webhookUrl: url,
        fileId: file.id,
      );
      if (ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: Color(0xFF10B981),
              content: Text('تم حذف النسخة من Drive بنجاح'),
            ),
          );
          _fetchCloudBackupsList();
        }
      } else {
        if (mounted) _showErrorSnackBar('تعذر حذف الملف من Drive');
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('خطأ أثناء الحذف: $e');
    }
  }

  void _copyScriptCode() {
    Clipboard.setData(
        ClipboardData(text: GoogleWebhookService.defaultScriptCode));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF6366F1),
        content: Row(
          children: [
            Icon(Icons.copy_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('تم نسخ كود Google Apps Script إلى الحافظة بنجاح!'),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAutoCloudBackup(bool val) async {
    setState(() => _autoCloudBackupEnabled = val);
    await widget.database
        .setSetting('auto_cloud_backup_enabled', val ? 'true' : 'false');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: val ? const Color(0xFF8B5CF6) : Colors.grey.shade700,
          content: Text(
            val
                ? 'تم تفعيل النسخ السحابي التلقائي يومياً عند $_autoCloudBackupTime'
                : 'تم إيقاف النسخ السحابي التلقائي المجدول',
          ),
        ),
      );
    }
  }

  Future<void> _pickAutoCloudBackupTime() async {
    final parts = _autoCloudBackupTime.split(':');
    final initialHour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 22) : 22;
    final initialMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() => _autoCloudBackupTime = formatted);
      await widget.database.setSetting('auto_cloud_backup_time', formatted);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF8B5CF6),
            content: Text(
                'تم ضبط موعد النسخ السحابي التلقائي يومياً على $formatted'),
          ),
        );
      }
    }
  }
}
