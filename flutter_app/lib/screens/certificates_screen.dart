import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/cloud_sync_service.dart';
import '../core/database/database_service.dart';
import '../models/certificate_element_config.dart';
import '../models/exam_model.dart';
import '../models/group_model.dart';
import '../models/student_model.dart';
import '../widgets/circular_image_cropper_dialog.dart';

class CertificateStudentData {
  final String id;
  final String name;
  final String score;
  final String percent;
  final int rank;
  final String rankText;
  final String groupName;
  final String parentPhone;

  const CertificateStudentData({
    this.id = '',
    required this.name,
    required this.score,
    required this.percent,
    required this.rank,
    required this.rankText,
    required this.groupName,
    this.parentPhone = '',
  });
}

enum CertificateMode {
  examRankings, // أوائل الامتحانات ورصد الدرجات
  groupStudent, // تكريم طالب من مجموعة
  customFree,   // شهادة حرة مخصصة
}

class CertificatesScreen extends StatefulWidget {
  final DatabaseService database;
  final VoidCallback? onBack;
  final ExamModel? initialExam;
  final GroupModel? initialGroup;
  final StudentModel? initialStudent;

  const CertificatesScreen({
    super.key,
    required this.database,
    this.onBack,
    this.initialExam,
    this.initialGroup,
    this.initialStudent,
  });

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  final GlobalKey _certKey = GlobalKey();
  bool _isLoading = true;
  bool _isGenerating = false;

  // Language mode: false = Arabic (RTL), true = English (LTR)
  bool _isEnglish = false;

  List<ExamModel> _exams = [];
  ExamModel? _selectedExam;
  List<GroupModel> _groups = [];
  Map<String, List<StudentModel>> _groupStudentsMap = {};

  // Active Rank Tier selection
  RankTier _activeTier = RankTier.rank1;

  // Customized Styles per Tier (Top 3 have individual templates, Ranks 4-10 share a unified template)
  final Map<RankTier, CertificateStyle> _tierStyles = {
    RankTier.rank1: CertificateStyle.royal,
    RankTier.rank2: CertificateStyle.royal,
    RankTier.rank3: CertificateStyle.classic,
    RankTier.ranks4to10: CertificateStyle.classic,
  };

  // Customized Titles per Tier
  final Map<RankTier, String> _tierTitlesAr = {
    RankTier.rank1: 'شَهَادَةُ صَدَارَةٍ وَتَفَوُّقٍ مُطْلَق',
    RankTier.rank2: 'شَهَادَةُ امْتِيَازٍ وَتَقْدِيرٍ رَفِيع',
    RankTier.rank3: 'شَهَادَةُ نُبُوغٍ وَتَكْرِيمٍ مُتَمَيِّز',
    RankTier.ranks4to10: 'شَهَادَةُ تَفَوُّقٍ وَتَكْرِيمِ لَوْحَةِ الشَّرَف',
  };

  final Map<RankTier, String> _tierTitlesEn = {
    RankTier.rank1: 'SUPREME FIRST PLACE CERTIFICATE OF DISTINCTION',
    RankTier.rank2: 'SECOND PLACE CERTIFICATE OF EXCELLENCE',
    RankTier.rank3: 'THIRD PLACE CERTIFICATE OF MERIT',
    RankTier.ranks4to10: 'TOP 10 HONOR ROLL CERTIFICATE OF ACHIEVEMENT',
  };

  // Customized Commendation / Reasons per Tier
  final Map<RankTier, String> _tierReasonsAr = {
    RankTier.rank1:
        'تقديراً لتربعه على عرش الصدارة ونيله المركز الأول بكل جدارة واقتدار، مع أطيب التمنيات بدوام القمة والتألق.',
    RankTier.rank2:
        'تقديراً لحصوله المستحق على المركز الثاني وتفوقه الباهر، متمنين له استمرار النجاح والارتقاء نحو القمة.',
    RankTier.rank3:
        'تقديراً لاجتهاده المثمر وإحرازه المركز الثالث بكل جدارة واستحقاق، متمنين له دوام التقدم والازدهار.',
    RankTier.ranks4to10:
        'تقديراً لاجتهاده المشرف وتفوقه الملحوظ وانضمامه المستحق إلى لوحة شرف العشرة الأوائل المتميزين.',
  };

  final Map<RankTier, String> _tierReasonsEn = {
    RankTier.rank1:
        'In highest recognition of claiming 1st Place with supreme dedication and peerless academic distinction.',
    RankTier.rank2:
        'In honorable recognition of achieving 2nd Place with stellar performance and commendable perseverance.',
    RankTier.rank3:
        'In honorable recognition of achieving 3rd Place with impressive determination and academic passion.',
    RankTier.ranks4to10:
        'In proud recognition of being named to the Elite Honor Roll among the Top 10 distinguished students.',
  };

  // Fine-tuned element layouts per tier and style loaded from SQLite Studio settings
  final Map<String, CertificateTierLayout> _layouts = {};

  int _selectedStudentIndex = 0;
  List<CertificateStudentData> _studentsRanked = [];
  final Set<String> _sentCertStudentIds = {};

  // Persistent settings from database
  String _centerName = 'أكاديمية المعلم الذكي';
  String _teacherName = 'أ/ عادل سليمان';
  String _customLogoPath = '';
  String _certCustomImagePath = '';

  // Custom in-place editable overrides for the certificate
  String? _customStudentName;
  String? _customCertTitle;
  String? _customCenterName;
  String? _customTeacherName;
  String? _customExamTitle;
  String? _customRankText;
  String? _customReasonText;
  String? _customDate;

  // وضع إعداد الشهادات الحالي (الأوائل / طالب بالمجموعة / شهادة حرة)
  CertificateMode _certMode = CertificateMode.examRankings;
  GroupModel? _selectedGroup;
  StudentModel? _selectedStudent;
  String _selectedPresetRank = '🌟 وسام التفوق والتميز الدراسي';
  String _selectedPresetReason =
      'تقديراً لاجتهاده المثمر وتفوقه العلمي الباهر وحرصه الدائم على التميز والارتقاء والتألق المستمر.';

  final TextEditingController _customFreeStudentCtrl = TextEditingController();
  final TextEditingController _customFreeTitleCtrl = TextEditingController();
  final TextEditingController _customFreeRankCtrl = TextEditingController();
  final TextEditingController _customFreeReasonCtrl = TextEditingController();
  final TextEditingController _customFreeOccasionCtrl = TextEditingController();
  final TextEditingController _customFreePhoneCtrl = TextEditingController();

  final List<Map<String, String>> _commendationPresetsAr = [
    {
      'title': 'تفوق دراسي باهر',
      'rank': '🌟 وسام التفوق والتميز الدراسي',
      'reason':
          'تقديراً لاجتهاده المثمر وتفوقه العلمي الباهر وحرصه الدائم على التميز والارتقاء والتألق المستمر.',
    },
    {
      'title': 'الطالب المثالي والسلوك القويم',
      'rank': '👑 وسام الطالب المثالي والأخلاق الرفيعة',
      'reason':
          'تقديراً لأخلاقه الفاضلة وسلوكه النموذجي المتميز والتزامه الراقي مع زملائه ومعلميه.',
    },
    {
      'title': 'إتقان واجتياز المنهج',
      'rank': '📜 وسام استيعاب وإتقان المنهج',
      'reason':
          'تقديراً لاجتيازه متطلبات المنهج الدراسي بنجاح واقتدار وإظهاره مهارات استيعاب استثنائية.',
    },
    {
      'title': 'الالتزام الكامل بالحضور',
      'rank': '⏰ وسام الانضباط والحضور المثالي',
      'reason':
          'تقديراً لانضباطه الرائع وحرصه الدائم على الحضور دون غياب والمشاركة الفعالة في الحصص.',
    },
    {
      'title': 'اجتياز كورس البرمجة والذكاء الاصطناعي',
      'rank': '💻 وسام إتقان التكنولوجيا والبرمجة',
      'reason':
          'تقديراً لإتمامه متطلبات دورة البرمجة والتقنية بنجاح وتفوق، وإبداعه في المشاريع التطبيقية.',
    },
    {
      'title': 'حفظ ومراجعة القرآن الكريم',
      'rank': '📖 وسام الشرف والتميز القرآني',
      'reason':
          'تقديراً لجهوده المباركة في حفظ ومراجعة آيات الذكر الحكيم، بارك الله فيه ونفع به أهله.',
    },
    {
      'title': 'تكريم واجتهاد شهري',
      'rank': '🎖️ نجم الشهر وأيقونة الاجتهاد',
      'reason':
          'تقديراً لاجتهاده الملحوظ وتطوره المستمر ونشاطه المميز خلال هذا الشهر، متمنين له دوام التألق.',
    },
  ];

  final List<Map<String, String>> _commendationPresetsEn = [
    {
      'title': 'Academic Excellence',
      'rank': '🌟 Medal of Academic Distinction',
      'reason':
          'In recognition of outstanding dedication, stellar academic achievement, and relentless pursuit of excellence.',
    },
    {
      'title': 'Ideal Student & Ethics',
      'rank': '👑 Exemplary Student & Character Award',
      'reason':
          'In appreciation of exceptional character, exemplary behavior, and admirable teamwork with peers and teachers.',
    },
    {
      'title': 'Curriculum Mastery',
      'rank': '📜 Certificate of Curriculum Mastery',
      'reason':
          'In recognition of successfully mastering all course requirements with top comprehension and skill.',
    },
    {
      'title': 'Perfect Attendance',
      'rank': '⏰ Perfect Attendance & Discipline Award',
      'reason':
          'In recognition of remarkable discipline, 100% attendance, and enthusiastic classroom participation.',
    },
    {
      'title': 'Coding & AI Mastery',
      'rank': '💻 Tech & Programming Honors',
      'reason':
          'In recognition of successfully completing advanced tech coursework and demonstrating creativity in practical projects.',
    },
    {
      'title': 'Monthly Star Student',
      'rank': '🎖️ Star of the Month Award',
      'reason':
          'In celebration of impressive progress, active dedication, and standout accomplishments throughout the month.',
    },
  ];

  static const String _defaultArReason =
      'تقديراً لاجتهاده المتميز وتفوقه الباهر وحصوله على أعلى الدرجات بكل جدارة واقتدار.';
  static const String _defaultEnReason =
      'In recognition of outstanding dedication, academic excellence, and achieving the highest distinction.';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _customFreeStudentCtrl.dispose();
    _customFreeTitleCtrl.dispose();
    _customFreeRankCtrl.dispose();
    _customFreeReasonCtrl.dispose();
    _customFreeOccasionCtrl.dispose();
    _customFreePhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _centerName = await widget.database.getSetting('center_name', defaultValue: 'أكاديمية المعلم الذكي');
      _teacherName = await widget.database.getSetting('teacher_name', defaultValue: 'أ/ عادل سليمان');
      _customLogoPath = await widget.database.getSetting('custom_logo_path', defaultValue: '');
      _certCustomImagePath = await widget.database.getSetting('cert_custom_top_image_path', defaultValue: '');

      // Load persistent tier preferences (templates and wording for 1st, 2nd, 3rd, and 4-10)
      await _loadTierSettings();

      final fetchedExams = await widget.database.getExams();
      final fetchedGroups = await widget.database.getGroups();

      final Map<String, List<StudentModel>> gStudents = {};
      for (final g in fetchedGroups) {
        gStudents[g.id] = await widget.database.getStudents(groupId: g.id);
      }

      _exams = fetchedExams;
      _groups = fetchedGroups;
      _groupStudentsMap = gStudents;

      if (widget.initialGroup != null) {
        _selectedGroup = _groups.where((g) => g.id == widget.initialGroup!.id).firstOrNull ?? widget.initialGroup;
      } else if (_groups.isNotEmpty) {
        _selectedGroup = _groups.first;
      }

      if (_selectedGroup != null) {
        final list = _groupStudentsMap[_selectedGroup!.id] ?? [];
        if (widget.initialStudent != null) {
          _selectedStudent = widget.initialStudent;
        } else if (list.isNotEmpty) {
          _selectedStudent = list.first;
        }
      }

      if (widget.initialExam != null) {
        _selectedExam = _exams.where((e) => e.id == widget.initialExam!.id).firstOrNull ?? widget.initialExam;
        _certMode = CertificateMode.examRankings;
        await _loadStudentsForExam(_selectedExam!);
      } else if (widget.initialStudent != null || widget.initialGroup != null) {
        _certMode = CertificateMode.groupStudent;
      } else if (_exams.isNotEmpty) {
        _selectedExam = _exams.first;
        await _loadStudentsForExam(_selectedExam!);
      } else {
        _studentsRanked = [];
        _certMode = CertificateMode.groupStudent;
      }
    } catch (e) {
      debugPrint('Error loading certificates data: $e');
      _studentsRanked = [];
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTierSettings() async {
    for (final tier in RankTier.values) {
      final styleVal = await widget.database.getSetting('cert_tier_style_${tier.name}');
      if (styleVal.isNotEmpty) {
        final found = CertificateStyle.values.where((e) => e.name == styleVal).firstOrNull;
        if (found != null) _tierStyles[tier] = found;
      }
      final titleAr = await widget.database.getSetting('cert_tier_title_ar_${tier.name}');
      if (titleAr.isNotEmpty) _tierTitlesAr[tier] = titleAr;

      final titleEn = await widget.database.getSetting('cert_tier_title_en_${tier.name}');
      if (titleEn.isNotEmpty) _tierTitlesEn[tier] = titleEn;

      final reasonAr = await widget.database.getSetting('cert_tier_reason_ar_${tier.name}');
      if (reasonAr.isNotEmpty) _tierReasonsAr[tier] = reasonAr;

      final reasonEn = await widget.database.getSetting('cert_tier_reason_en_${tier.name}');
      if (reasonEn.isNotEmpty) _tierReasonsEn[tier] = reasonEn;

      // Load Studio custom element positions, fonts, colors, and sizes
      for (final s in CertificateStyle.values) {
        final layoutKey = 'cert_layout_${tier.name}_${s.name}';
        final layoutJson = await widget.database.getSetting(layoutKey);
        if (layoutJson.isNotEmpty) {
          _layouts['${tier.name}_${s.name}'] = CertificateTierLayout.fromJsonString(tier, s, layoutJson);
        }
      }
    }
  }

  CertificateTierLayout get _currentLayout {
    final tier = _currentTier;
    final style = _selectedStyle;
    final key = '${tier.name}_${style.name}';
    return _layouts[key] ?? CertificateTierLayout.defaultFor(tier, style);
  }

  Widget _applyTransform(CertificateElementType type, Widget child) {
    final cfg = _currentLayout.getConfig(type);
    if (!cfg.isVisible) return const SizedBox.shrink();
    Widget w = child;
    if (cfg.scale != 1.0) {
      w = Transform.scale(scale: cfg.scale, child: w);
    }
    if (cfg.rotation != 0.0) {
      w = Transform.rotate(angle: cfg.rotation * 3.141592653589793 / 180.0, child: w);
    }
    if (cfg.dx != 0.0 || cfg.dy != 0.0) {
      w = Transform.translate(offset: Offset(cfg.dx, cfg.dy), child: w);
    }
    return w;
  }

  TextStyle _applyTextStyle(CertificateElementType type, TextStyle fallback) {
    final cfg = _currentLayout.getConfig(type);
    FontWeight weight = fallback.fontWeight ?? FontWeight.normal;
    if (cfg.fontWeightIndex >= 0 && cfg.fontWeightIndex < 6) {
      weight = cfg.fontWeight;
    }
    return fallback.copyWith(
      fontSize: cfg.fontSize > 0 ? cfg.fontSize : fallback.fontSize,
      fontFamily: cfg.fontFamily.isNotEmpty ? cfg.fontFamily : fallback.fontFamily,
      fontWeight: weight,
      fontStyle: cfg.isItalic ? FontStyle.italic : fallback.fontStyle,
      color: cfg.colorValue != 0 ? Color(cfg.colorValue) : fallback.color,
      letterSpacing: cfg.letterSpacing != 0.0 ? cfg.letterSpacing : fallback.letterSpacing,
      decoration: cfg.isUnderline ? TextDecoration.underline : fallback.decoration,
      shadows: cfg.shadows ?? fallback.shadows,
    );
  }

  Future<void> _saveTierSettings(RankTier tier) async {
    await widget.database.setSetting('cert_tier_style_${tier.name}', _tierStyles[tier]?.name ?? '');
    await widget.database.setSetting('cert_tier_title_ar_${tier.name}', _tierTitlesAr[tier] ?? '');
    await widget.database.setSetting('cert_tier_title_en_${tier.name}', _tierTitlesEn[tier] ?? '');
    await widget.database.setSetting('cert_tier_reason_ar_${tier.name}', _tierReasonsAr[tier] ?? '');
    await widget.database.setSetting('cert_tier_reason_en_${tier.name}', _tierReasonsEn[tier] ?? '');
  }

  Future<void> _saveCurrentLayout() async {
    final tier = _currentTier;
    final style = _selectedStyle;
    final key = '${tier.name}_${style.name}';
    _layouts[key] = _currentLayout;
    await widget.database.setSetting('cert_layout_$key', _currentLayout.toJson());
  }

  Future<void> _loadStudentsForExam(ExamModel exam) async {
    try {
      final scoresMap = await widget.database.getExamScoresForExam(exam.id);
      if (scoresMap.isEmpty) {
        setState(() {
          _studentsRanked = [];
          _selectedStudentIndex = 0;
          _resetCustomOverrides();
        });
        return;
      }

      // Collect candidates: exam's group + any group in memory + fetch from DB if needed
      final Map<String, StudentModel> candidateMap = {};
      if (_groupStudentsMap.containsKey(exam.groupId)) {
        for (final s in _groupStudentsMap[exam.groupId]!) {
          candidateMap[s.id] = s;
        }
      }
      for (final gStudents in _groupStudentsMap.values) {
        for (final s in gStudents) {
          if (scoresMap.containsKey(s.id)) {
            candidateMap[s.id] = s;
          }
        }
      }
      if (scoresMap.keys.any((id) => !candidateMap.containsKey(id))) {
        final allDbStudents = await widget.database.getStudents();
        for (final s in allDbStudents) {
          if (scoresMap.containsKey(s.id)) {
            candidateMap[s.id] = s;
          }
        }
      }

      final List<MapEntry<StudentModel, double>> scoredStudents = [];
      for (final entry in scoresMap.entries) {
        final s = candidateMap[entry.key];
        if (s != null) {
          scoredStudents.add(MapEntry(s, entry.value));
        }
      }

      if (scoredStudents.isEmpty) {
        setState(() {
          _studentsRanked = [];
          _selectedStudentIndex = 0;
          _resetCustomOverrides();
        });
        return;
      }

      scoredStudents.sort((a, b) => b.value.compareTo(a.value));

      final examGroup = _groups.where((g) => g.id == exam.groupId).firstOrNull;

      final List<CertificateStudentData> list = [];
      for (int i = 0; i < scoredStudents.length && i < 10; i++) {
        final entry = scoredStudents[i];
        final rank = i + 1;
        String rankLabel;
        if (rank == 1) {
          rankLabel = '🥇 المركز الأول (صدارة المجموعة)';
        } else if (rank == 2) {
          rankLabel = '🥈 المركز الثاني (وصافة الشرف)';
        } else if (rank == 3) {
          rankLabel = '🥉 المركز الثالث (منصة التتويج)';
        } else {
          rankLabel = '🎖️ المركز رقم $rank (لوحة الشرف)';
        }

        final pct = exam.maxScore > 0 ? (entry.value / exam.maxScore) * 100 : 0.0;
        final studentGroup = _groups.where((g) => g.id == entry.key.groupId).firstOrNull;
        final finalGroupName = studentGroup?.name ?? (examGroup?.name ?? 'المجموعة العامة');

        list.add(CertificateStudentData(
          id: entry.key.id,
          name: entry.key.fullName,
          score: '${entry.value.toStringAsFixed(1).replaceAll(".0", "")} / ${exam.maxScore.toStringAsFixed(0)}',
          percent: '${pct.toStringAsFixed(0)}%',
          rank: rank,
          rankText: rankLabel,
          groupName: finalGroupName,
          parentPhone: entry.key.parentPhone,
        ));
      }

      final sentCerts = await widget.database.getSentStudentIdsStrict(
        category: 'certificate',
        contextKey: exam.id,
      );

      int initialIdx = 0;
      if (widget.initialStudent != null) {
        final foundIdx = list.indexWhere((s) => s.id == widget.initialStudent!.id);
        if (foundIdx >= 0) initialIdx = foundIdx;
      }
      final selectedRank = list.isNotEmpty ? list[initialIdx].rank : 1;

      setState(() {
        _sentCertStudentIds.clear();
        _sentCertStudentIds.addAll(sentCerts);
        _studentsRanked = list;
        _selectedStudentIndex = initialIdx;
        _activeTier = selectedRank == 1
            ? RankTier.rank1
            : (selectedRank == 2 ? RankTier.rank2 : (selectedRank == 3 ? RankTier.rank3 : RankTier.ranks4to10));
        _resetCustomOverrides();
      });
    } catch (e) {
      debugPrint('Error loading students for exam: $e');
      setState(() {
        _studentsRanked = [];
        _selectedStudentIndex = 0;
        _resetCustomOverrides();
      });
    }
  }

  void _resetCustomOverrides() {
    _customStudentName = null;
    _customCertTitle = null;
    _customCenterName = null;
    _customTeacherName = null;
    _customExamTitle = null;
    _customRankText = null;
    _customReasonText = null;
    _customDate = null;
  }

  RankTier get _currentTier {
    if (_studentsRanked.isNotEmpty && _selectedStudentIndex >= 0 && _selectedStudentIndex < _studentsRanked.length) {
      final rank = _studentsRanked[_selectedStudentIndex].rank;
      if (rank == 1) return RankTier.rank1;
      if (rank == 2) return RankTier.rank2;
      if (rank == 3) return RankTier.rank3;
      return RankTier.ranks4to10;
    }
    return _activeTier;
  }

  CertificateStyle get _selectedStyle {
    return _tierStyles[_currentTier] ?? CertificateStyle.royal;
  }

  void _selectTier(RankTier tier) {
    HapticFeedback.selectionClick();
    setState(() {
      _activeTier = tier;
      _resetCustomOverrides();
      if (_studentsRanked.isNotEmpty) {
        final idx = _studentsRanked.indexWhere((s) {
          if (tier == RankTier.rank1) return s.rank == 1;
          if (tier == RankTier.rank2) return s.rank == 2;
          if (tier == RankTier.rank3) return s.rank == 3;
          return s.rank >= 4;
        });
        if (idx != -1) {
          _selectedStudentIndex = idx;
        }
      }
    });
  }

  void _onStyleCardSelected(CertificateStyle style) {
    HapticFeedback.selectionClick();
    final tier = _currentTier;
    setState(() {
      _tierStyles[tier] = style;
      _customCertTitle = null;
    });
    _saveTierSettings(tier);
  }

  String _getTierDisplayName(RankTier tier, bool isEn) {
    if (isEn) {
      switch (tier) {
        case RankTier.rank1:
          return '🥇 1st Place';
        case RankTier.rank2:
          return '🥈 2nd Place';
        case RankTier.rank3:
          return '🥉 3rd Place';
        case RankTier.ranks4to10:
          return '🎖️ Ranks 4-10 (Unified)';
      }
    } else {
      switch (tier) {
        case RankTier.rank1:
          return '🥇 المركز الأول';
        case RankTier.rank2:
          return '🥈 المركز الثاني';
        case RankTier.rank3:
          return '🥉 المركز الثالث';
        case RankTier.ranks4to10:
          return '🎖️ المراكز (4 - 10) [شهادة موحدة]';
      }
    }
  }

  String _getStyleName(CertificateStyle style, bool isEn) {
    switch (style) {
      case CertificateStyle.royal:
        return isEn ? 'Royal Gold' : 'الذهبي الملكي الفاخر 👑';
      case CertificateStyle.classic:
        return isEn ? 'Academic Diploma' : 'الدبلوم الأكاديمي الرسمي 🏛️';
      case CertificateStyle.natureWood:
        return isEn ? 'Nature & Wood' : 'الخشبي المستوحى من الطبيعة 🌿';
    }
  }

  String _getEnglishRank(int rank) {
    if (rank == 1) return '🥇 1st Place (Top of Cohort)';
    if (rank == 2) return '🥈 2nd Place (Runner-Up)';
    if (rank == 3) return '🥉 3rd Place (Distinction)';
    return '🎖️ Rank #$rank (Honor Roll)';
  }

  String _getDefaultTitleForStyle(CertificateStyle style, bool isEn) {
    if (isEn) {
      switch (style) {
        case CertificateStyle.royal:
          return 'CERTIFICATE OF EXCELLENCE & HONOR';
        case CertificateStyle.classic:
          return 'DIPLOMA OF MERIT & DISTINCTION';
        case CertificateStyle.natureWood:
          return 'CERTIFICATE OF MERIT & HIGHEST HONORS';
      }
    } else {
      switch (style) {
        case CertificateStyle.royal:
          return 'شَهَادَةُ تَقْدِيرٍ وَتَفَوُّقٍ مَلَكِيَّة';
        case CertificateStyle.classic:
          return 'شَــــهَــــادَةُ جَــــدَارَةٍ وَتَــــقْــــدِيــــر';
        case CertificateStyle.natureWood:
          return 'شَهَادَةُ تَقْدِيرٍ وَتَفَوُّقٍ مَعَ مَرْتَبَةِ الشَّرَفِ الأُولَى';
      }
    }
  }

  // Active Effective Values
  String get _effStudentName {
    if (_customStudentName != null && _customStudentName!.trim().isNotEmpty) {
      return _customStudentName!;
    }
    if (_certMode == CertificateMode.groupStudent && _selectedStudent != null) {
      return _selectedStudent!.fullName;
    }
    if (_certMode == CertificateMode.customFree && _customFreeStudentCtrl.text.trim().isNotEmpty) {
      return _customFreeStudentCtrl.text.trim();
    }
    if (_studentsRanked.isNotEmpty) {
      return _studentsRanked[_selectedStudentIndex].name;
    }
    return _isEnglish ? 'Distinguished Student' : 'اسم الطالب المكرم';
  }

  String get _effCenterName {
    if (_customCenterName != null && _customCenterName!.trim().isNotEmpty) {
      return _customCenterName!;
    }
    return _centerName;
  }

  String get _effTeacherName {
    if (_customTeacherName != null && _customTeacherName!.trim().isNotEmpty) {
      return _customTeacherName!;
    }
    return _teacherName;
  }

  String get _effCertTitle {
    if (_customCertTitle != null && _customCertTitle!.trim().isNotEmpty) {
      return _customCertTitle!;
    }
    if (_certMode == CertificateMode.customFree && _customFreeTitleCtrl.text.trim().isNotEmpty) {
      return _customFreeTitleCtrl.text.trim();
    }
    final tier = _currentTier;
    final customTitle = _isEnglish ? _tierTitlesEn[tier] : _tierTitlesAr[tier];
    if (customTitle != null && customTitle.trim().isNotEmpty) {
      return customTitle;
    }
    return _getDefaultTitleForStyle(_selectedStyle, _isEnglish);
  }

  String get _effExamTitle {
    if (_customExamTitle != null && _customExamTitle!.trim().isNotEmpty) {
      return _customExamTitle!;
    }
    if (_certMode == CertificateMode.groupStudent && _selectedGroup != null) {
      return _selectedGroup!.name;
    }
    if (_certMode == CertificateMode.customFree && _customFreeOccasionCtrl.text.trim().isNotEmpty) {
      return _customFreeOccasionCtrl.text.trim();
    }
    return _selectedExam?.title ?? (_isEnglish ? 'Computer Science & AI' : 'حاسب آلي وتكنولوجيا المعلومات');
  }

  String get _effRankText {
    if (_customRankText != null && _customRankText!.trim().isNotEmpty) {
      return _customRankText!;
    }
    if (_certMode == CertificateMode.groupStudent) {
      return _selectedPresetRank;
    }
    if (_certMode == CertificateMode.customFree && _customFreeRankCtrl.text.trim().isNotEmpty) {
      return _customFreeRankCtrl.text.trim();
    }
    if (_studentsRanked.isNotEmpty) {
      final s = _studentsRanked[_selectedStudentIndex];
      return _isEnglish ? _getEnglishRank(s.rank) : s.rankText;
    }
    switch (_currentTier) {
      case RankTier.rank1:
        return _isEnglish ? '🥇 1st Place (Top of Cohort)' : '🥇 المركز الأول (صدارة المجموعة)';
      case RankTier.rank2:
        return _isEnglish ? '🥈 2nd Place (Runner-Up)' : '🥈 المركز الثاني (وصافة الشرف)';
      case RankTier.rank3:
        return _isEnglish ? '🥉 3rd Place (Distinction)' : '🥉 المركز الثالث (منصة التتويج)';
      case RankTier.ranks4to10:
        return _isEnglish ? '🎖️ Top 10 Honor Roll' : '🎖️ قائمة لوحة شرف العشرة الأوائل';
    }
  }

  String get _effReason {
    if (_customReasonText != null && _customReasonText!.trim().isNotEmpty) {
      return _customReasonText!;
    }
    if (_certMode == CertificateMode.groupStudent) {
      return _selectedPresetReason;
    }
    if (_certMode == CertificateMode.customFree && _customFreeReasonCtrl.text.trim().isNotEmpty) {
      return _customFreeReasonCtrl.text.trim();
    }
    final tier = _currentTier;
    final customReason = _isEnglish ? _tierReasonsEn[tier] : _tierReasonsAr[tier];
    if (customReason != null && customReason.trim().isNotEmpty) {
      return customReason;
    }
    return _isEnglish ? _defaultEnReason : _defaultArReason;
  }

  String get _effGroupName {
    if (_certMode == CertificateMode.groupStudent && _selectedGroup != null) {
      return _selectedGroup!.name;
    }
    if (_studentsRanked.isNotEmpty && _selectedStudentIndex < _studentsRanked.length) {
      return _studentsRanked[_selectedStudentIndex].groupName;
    }
    return '';
  }

  String get _effParentPhone {
    if (_certMode == CertificateMode.groupStudent && _selectedStudent != null) {
      return _selectedStudent!.parentPhone;
    }
    if (_certMode == CertificateMode.customFree && _customFreePhoneCtrl.text.trim().isNotEmpty) {
      return _customFreePhoneCtrl.text.trim();
    }
    if (_studentsRanked.isNotEmpty && _selectedStudentIndex < _studentsRanked.length) {
      return _studentsRanked[_selectedStudentIndex].parentPhone;
    }
    return '';
  }

  String get _effDate {
    if (_customDate != null && _customDate!.trim().isNotEmpty) {
      return _customDate!;
    }
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  /// Pick official custom logo from phone storage and save it in database
  Future<void> _pickOfficialLogo() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty || result.first.path == null) return;

      final pickedFile = File(result.first.path!);
      if (!pickedFile.existsSync()) return;

      if (!mounted) return;
      final croppedFile = await CircularImageCropper.cropImage(
        context,
        imagePath: pickedFile.path,
        title: _isEnglish ? 'Crop Official Center Logo' : 'قص وتعديل لوجو السنتر الرسمي (السفلي)',
        isBottomSeal: true,
      );
      if (croppedFile == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final logosDir = Directory('${appDir.path}/official_logos');
      if (!logosDir.existsSync()) logosDir.createSync(recursive: true);

      final ext = croppedFile.path.contains('.') ? croppedFile.path.split('.').last : 'png';
      final savedLogo = await croppedFile.copy('${logosDir.path}/system_logo_${DateTime.now().millisecondsSinceEpoch}.$ext');

      await widget.database.setSetting('custom_logo_path', savedLogo.path);
      await widget.database.setSetting('custom_app_icon_path', savedLogo.path);

      setState(() {
        _customLogoPath = savedLogo.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEnglish ? 'Official system logo updated successfully! 🏫✨' : 'تم اعتماد وتعيين لوجو المنظومة بنجاح! 🏫✨'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error picking official logo: $e');
    }
  }

  /// Re-crop the current official center logo (zoom in/out and pan inside circle)
  Future<void> _recropOfficialLogo() async {
    try {
      if (_customLogoPath.isEmpty || !File(_customLogoPath).existsSync()) {
        await _pickOfficialLogo();
        return;
      }

      if (!mounted) return;
      final croppedFile = await CircularImageCropper.cropImage(
        context,
        imagePath: _customLogoPath,
        title: _isEnglish ? 'Adjust & Crop Official Logo' : 'تكبير وتحريك وقص اللوجو الرسمي (السفلي)',
        isBottomSeal: true,
      );
      if (croppedFile == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final logosDir = Directory('${appDir.path}/official_logos');
      if (!logosDir.existsSync()) logosDir.createSync(recursive: true);

      final ext = croppedFile.path.contains('.') ? croppedFile.path.split('.').last : 'png';
      final savedLogo = await croppedFile.copy('${logosDir.path}/system_logo_${DateTime.now().millisecondsSinceEpoch}.$ext');

      await widget.database.setSetting('custom_logo_path', savedLogo.path);
      await widget.database.setSetting('custom_app_icon_path', savedLogo.path);

      setState(() {
        _customLogoPath = savedLogo.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEnglish ? 'Official logo adjusted successfully! 🏫✨' : 'تم تعديل وتكبير/تحريك اللوجو الرسمي بنجاح! 🏫✨'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error re-cropping official logo: $e');
    }
  }

  /// Pick custom top picture for the certificate with circular cropper (Zoom & Pan)
  Future<void> _pickCertificateTopImage() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty || result.first.path == null) return;

      final pickedFile = File(result.first.path!);
      if (!pickedFile.existsSync()) return;

      if (!mounted) return;
      final croppedFile = await CircularImageCropper.cropImage(
        context,
        imagePath: pickedFile.path,
        title: _isEnglish ? 'Crop Top Logo' : 'قص وتعديل اللوجو العلوي للشهادة',
        isBottomSeal: false,
      );
      if (croppedFile == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final certImgDir = Directory('${appDir.path}/cert_images');
      if (!certImgDir.existsSync()) certImgDir.createSync(recursive: true);

      final ext = croppedFile.path.contains('.') ? croppedFile.path.split('.').last : 'png';
      final savedPath = '${certImgDir.path}/cert_top_img_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final savedImg = await croppedFile.copy(savedPath);

      await widget.database.setSetting('cert_custom_top_image_path', savedImg.path);

      setState(() {
        _certCustomImagePath = savedImg.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEnglish ? 'Certificate top logo updated successfully! 🖼️✨' : 'تم تعيين وتعديل اللوجو العلوي بنجاح! 🖼️✨'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error picking certificate top image: $e');
    }
  }

  /// Re-crop the current top certificate image (zoom in/out and pan inside the circle)
  Future<void> _recropCertificateTopImage() async {
    try {
      if (_certCustomImagePath.isEmpty || !File(_certCustomImagePath).existsSync()) {
        await _pickCertificateTopImage();
        return;
      }

      if (!mounted) return;
      final croppedFile = await CircularImageCropper.cropImage(
        context,
        imagePath: _certCustomImagePath,
        title: _isEnglish ? 'Adjust & Crop Top Logo' : 'تكبير وتحريك وقص اللوجو العلوي',
        isBottomSeal: false,
      );
      if (croppedFile == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final certImgDir = Directory('${appDir.path}/cert_images');
      if (!certImgDir.existsSync()) certImgDir.createSync(recursive: true);

      final ext = croppedFile.path.contains('.') ? croppedFile.path.split('.').last : 'png';
      final savedPath = '${certImgDir.path}/cert_top_img_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final savedImg = await croppedFile.copy(savedPath);

      await widget.database.setSetting('cert_custom_top_image_path', savedImg.path);

      setState(() {
        _certCustomImagePath = savedImg.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEnglish ? 'Top logo adjusted successfully! 🖼️✨' : 'تم تعديل وتكبير/تحريك اللوجو العلوي بنجاح! 🖼️✨'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error re-cropping certificate top image: $e');
    }
  }

  /// Bottom sheet dialog to change, crop, or clear the top certificate logo
  Future<void> _showTopImageOptions() async {
    final hasCustom = _certCustomImagePath.isNotEmpty && File(_certCustomImagePath).existsSync();
    final hasOfficial = _customLogoPath.isNotEmpty && File(_customLogoPath).existsSync();

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.photo_library_rounded, color: Color(0xFFD4AF37), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      _isEnglish ? 'Certificate Top Logo' : 'اللوجو العلوي للشهادة',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _isEnglish
                      ? 'Pick, zoom, pan, crop, and adjust position on the certificate'
                      : 'اختيار الصورة وقصها بالدائرة وتكبيرها وتصغيرها وتحريك موقعها بدقة متناهية',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 16),

                // Option 1: Pick new image from gallery and crop
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF60A5FA)),
                  ),
                  title: Text(
                    hasCustom
                        ? (_isEnglish ? 'Choose New Image from Phone' : 'اختيار صورة جديدة من الهاتف وقصها')
                        : (_isEnglish ? 'Choose Image from Phone' : 'اختيار صورة من الهاتف وقصها بالدائرة'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _isEnglish ? 'Zoom in/out and pan in all directions inside circle' : 'تحديد صورة مع التكبير/التصغير والتحريك يمين وشمال وفوق وتحت داخل الدائرة',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickCertificateTopImage();
                  },
                ),

                // Option 2: Re-crop & adjust current image if exists
                if (hasCustom)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.crop_rotate_rounded, color: Color(0xFF34D399)),
                    ),
                    title: Text(
                      _isEnglish ? 'Re-adjust Current Logo (Zoom & Pan)' : 'إعادة تعديل وتكبير/تحريك الصورة الحالية',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isEnglish ? 'Zoom in/out and move the current image inside the circle' : 'فتح أداة القص لتكبيرها أو تصغيرها أو تحريك موضعها بدقة متناهية',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _recropCertificateTopImage();
                    },
                  ),

                // Option 3: Adjust Size & Position on Certificate with Live Preview
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.open_with_rounded, color: Color(0xFFFBBF24)),
                  ),
                  title: Text(
                    _isEnglish ? 'Adjust Position & Size on Certificate' : 'التحكم في موضع وحجم اللوجو بالشهادة',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _isEnglish ? 'Move left/right, up/down, and resize with live preview' : 'تحريك لأعلى ولأسفل ويميناً ويساراً وتكبير/تصغير بمعاينة حية',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showLogoAdjustModal(isBottomSeal: false);
                  },
                ),

                // Option 4: Use same official center logo
                if (hasOfficial)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.verified_rounded, color: Color(0xFF00F2FE)),
                    ),
                    title: Text(
                      _isEnglish ? 'Use Official Center Logo (Same as Bottom)' : 'استخدام نفس لوجو السنتر الرسمي (المعتمد بالسفل)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isEnglish ? 'Apply center logo to the top certificate badge' : 'توحيد اللوجو العلوي ليكون مطابقاً للوجو السنتر الرسمي',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await widget.database.setSetting('cert_custom_top_image_path', _customLogoPath);
                      setState(() {
                        _certCustomImagePath = _customLogoPath;
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isEnglish ? 'Official center logo applied to top badge! 🏫' : 'تم تعيين لوجو السنتر كاللوجو العلوي بنجاح! 🏫'),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),

                // Option 5: Delete / Reset
                if (hasCustom) ...[
                  const Divider(color: Colors.white12),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    ),
                    title: Text(
                      _isEnglish ? 'Reset to Default Emblem' : 'إزالة والعودة للشعار الافتراضي',
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isEnglish ? 'Remove custom picture from top' : 'إزالة الصورة المخصصة والعودة لشعار التفوق',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await widget.database.setSetting('cert_custom_top_image_path', '');
                      setState(() {
                        _certCustomImagePath = '';
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isEnglish ? 'Custom picture removed' : 'تم إزالة الصورة المخصصة والعودة للشعار الافتراضي'),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Bottom sheet dialog to change, crop, or adjust the official center / bottom logo
  Future<void> _showOfficialLogoOptions() async {
    final hasOfficial = _customLogoPath.isNotEmpty && File(_customLogoPath).existsSync();

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      _isEnglish ? 'Official Center / Bottom Logo' : 'لوجو السنتر الرسمي (الختم السفلي)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _isEnglish
                      ? 'Change, re-crop, or adjust position & scale of the official seal'
                      : 'تغيير الصورة، وإعادة قصها بالدائرة وتكبيرها، والتحكم في موضعها وحجمها على الشهادة',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 16),

                // Option 1: Pick new image
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF10B981)),
                  ),
                  title: Text(
                    hasOfficial
                        ? (_isEnglish ? 'Choose New Image from Phone' : 'اختيار صورة جديدة من الهاتف وقصها')
                        : (_isEnglish ? 'Choose Image from Phone' : 'اختيار صورة من الهاتف وقصها بالدائرة'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _isEnglish ? 'Zoom & pan inside the circular seal' : 'تكبير، تصغير، وتحريك بحرية داخل الدائرة مع دقة 100%',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickOfficialLogo();
                  },
                ),

                // Option 2: Re-crop current logo
                if (hasOfficial)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.crop_rotate_rounded, color: Color(0xFF00F2FE)),
                    ),
                    title: Text(
                      _isEnglish ? 'Re-adjust Current Logo (Zoom & Pan)' : 'إعادة تعديل وتكبير/تحريك الصورة الحالية',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isEnglish ? 'Move & scale current logo inside circle' : 'فتح أداة القص لتكبيرها أو تصغيرها أو تحريك موضعها بدقة',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _recropOfficialLogo();
                    },
                  ),

                // Option 3: Adjust Size & Position on certificate
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.open_with_rounded, color: Color(0xFFFBBF24)),
                  ),
                  title: Text(
                    _isEnglish ? 'Adjust Position & Size on Certificate' : 'التحكم في موضع وحجم الختم بالشهادة',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _isEnglish ? 'Move left/right, up/down, and resize with live preview' : 'تحريك لأعلى ولأسفل ويميناً ويساراً وتكبير/تصغير بمعاينة حية',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showLogoAdjustModal(isBottomSeal: true);
                  },
                ),

                // Option 4: Delete / Reset
                if (hasOfficial) ...[
                  const Divider(color: Colors.white12),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    ),
                    title: Text(
                      _isEnglish ? 'Restore Default System Icon' : 'استعادة أيقونة المنظومة الافتراضية',
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isEnglish ? 'Reset official center logo to default' : 'إزالة الصورة المخصصة والعودة لشعار التطبيق الافتراضي',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await widget.database.setSetting('custom_logo_path', '');
                      setState(() {
                        _customLogoPath = '';
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isEnglish ? 'Official logo reset to default' : 'تمت استعادة لوجو المنظومة الافتراضي'),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Unified bottom sheet to control top certificate logo or bottom official seal
  /// sizing (scale up/down) and movement (left/right/up/down) with real-time interactive preview!
  void _showLogoAdjustModal({required bool isBottomSeal}) {
    final type = isBottomSeal ? CertificateElementType.seal : CertificateElementType.logo;
    final cfg = _currentLayout.getConfig(type);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final double currentScale = cfg.scale;
            final double currentDx = cfg.dx;
            final double currentDy = cfg.dy;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Header with close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: (isBottomSeal ? const Color(0xFF10B981) : const Color(0xFF00F2FE))
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isBottomSeal ? const Color(0xFF10B981) : const Color(0xFF00F2FE),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.open_with_rounded,
                                    color: isBottomSeal ? const Color(0xFF10B981) : const Color(0xFF00F2FE),
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isBottomSeal
                                            ? (_isEnglish ? 'Bottom Seal Position & Size' : 'موقع وحجم الختم السفلي')
                                            : (_isEnglish ? 'Top Logo Position & Size' : 'موقع وحجم الشعار العلوي'),
                                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        _isEnglish ? 'Live preview during movement & scaling' : 'معاينة حية فورية أثناء التحريك والتكبير/التصغير',
                                        style: const TextStyle(fontSize: 9.5, color: Colors.white54),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 16),

                      // REAL-TIME LIVE PREVIEW OF THE LOGO/SEAL ON CERTIFICATE
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F172A), Color(0xFF101935)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (isBottomSeal ? const Color(0xFF10B981) : const Color(0xFFD4AF37)).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  isBottomSeal
                                      ? (_isEnglish ? 'Live Seal Preview:' : 'معاينة حية للختم:')
                                      : (_isEnglish ? 'Live Logo Preview:' : 'معاينة حية للشعار:'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: isBottomSeal ? const Color(0xFF10B981) : const Color(0xFFD4AF37),
                                  ),
                                ),
                                Text(
                                  'X: ${currentDx.toInt()}px • Y: ${currentDy.toInt()}px • ${(currentScale * 100).toInt()}%',
                                  style: const TextStyle(fontSize: 9.5, color: Colors.white70, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 72,
                              child: Center(
                                child: Transform.translate(
                                  offset: Offset(currentDx * 0.4, currentDy * 0.4),
                                  child: Transform.scale(
                                    scale: currentScale.clamp(0.4, 2.5),
                                    child: isBottomSeal
                                        ? _buildHangingWaxSeal(const Color(0xFFD4AF37))
                                        : _buildCertificateTopImage(size: 48),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 1. Scale / Size Control
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.aspect_ratio_rounded, color: Color(0xFFFBBF24), size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _isEnglish ? 'Logo Size / Scale:' : 'حجم وتكبير الشعار:',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFBBF24), width: 1),
                            ),
                            child: Text(
                              '${(currentScale * 100).toInt()}%',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFFBBF24)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white70, size: 24),
                            tooltip: _isEnglish ? 'Decrease Size' : 'تصغير الشعار (-5%)',
                            onPressed: currentScale > 0.4
                                ? () {
                                    final val = (currentScale - 0.05).clamp(0.4, 2.5);
                                    setSheetState(() => cfg.scale = val);
                                    setState(() {});
                                    _saveCurrentLayout();
                                  }
                                : null,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFFFBBF24),
                                inactiveTrackColor: const Color(0xFF334155),
                                thumbColor: const Color(0xFFFBBF24),
                                overlayColor: const Color(0xFFFBBF24).withValues(alpha: 0.2),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: currentScale.clamp(0.4, 2.5),
                                min: 0.4,
                                max: 2.5,
                                divisions: 42,
                                onChanged: (val) {
                                  setSheetState(() => cfg.scale = val);
                                  setState(() {});
                                  _saveCurrentLayout();
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70, size: 24),
                            tooltip: _isEnglish ? 'Increase Size' : 'تكبير الشعار (+5%)',
                            onPressed: currentScale < 2.5
                                ? () {
                                    final val = (currentScale + 0.05).clamp(0.4, 2.5);
                                    setSheetState(() => cfg.scale = val);
                                    setState(() {});
                                    _saveCurrentLayout();
                                  }
                                : null,
                          ),
                        ],
                      ),

                      // Quick Size Presets
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _buildPresetChip(
                              label: _isEnglish ? 'Mini (70%)' : '🔍 مصغر (70%)',
                              isSelected: (currentScale - 0.70).abs() < 0.04,
                              onTap: () {
                                setSheetState(() => cfg.scale = 0.70);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                            const SizedBox(width: 6),
                            _buildPresetChip(
                              label: _isEnglish ? 'Default (100%)' : '👑 افتراضي (100%)',
                              isSelected: (currentScale - 1.0).abs() < 0.04,
                              onTap: () {
                                setSheetState(() => cfg.scale = 1.0);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                            const SizedBox(width: 6),
                            _buildPresetChip(
                              label: _isEnglish ? 'Large (130%)' : '🌟 كبير (130%)',
                              isSelected: (currentScale - 1.30).abs() < 0.04,
                              onTap: () {
                                setSheetState(() => cfg.scale = 1.30);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                            const SizedBox(width: 6),
                            _buildPresetChip(
                              label: _isEnglish ? 'Jumbo (165%)' : '🏆 ضخم (165%)',
                              isSelected: (currentScale - 1.65).abs() < 0.04,
                              onTap: () {
                                setSheetState(() => cfg.scale = 1.65);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 2. Horizontal Movement (Move Left / Right)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.swap_horiz_rounded, color: Color(0xFF00F2FE), size: 20),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _isEnglish ? 'Move Left / Right (Horizontal):' : 'التحريك يميناً ويساراً (أفقياً):',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF00F2FE), width: 1),
                            ),
                            child: Text(
                              currentDx == 0.0
                                  ? (_isEnglish ? 'Center (0)' : 'المنتصف (0)')
                                  : (currentDx > 0
                                      ? (_isEnglish ? 'Right +${currentDx.toInt()}px' : 'يمين +${currentDx.toInt()}px')
                                      : (_isEnglish ? 'Left ${currentDx.toInt()}px' : 'يسار ${currentDx.toInt()}px')),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF00F2FE)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 22),
                            tooltip: _isEnglish ? 'Move Left' : 'تحريك لليسار (-2px)',
                            onPressed: () {
                              final val = (currentDx - 2.0).clamp(-180.0, 180.0);
                              setSheetState(() => cfg.dx = val);
                              setState(() {});
                              _saveCurrentLayout();
                            },
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFF00F2FE),
                                inactiveTrackColor: const Color(0xFF334155),
                                thumbColor: const Color(0xFF00F2FE),
                                overlayColor: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: currentDx.clamp(-180.0, 180.0),
                                min: -180.0,
                                max: 180.0,
                                divisions: 180,
                                onChanged: (val) {
                                  setSheetState(() => cfg.dx = val);
                                  setState(() {});
                                  _saveCurrentLayout();
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 22),
                            tooltip: _isEnglish ? 'Move Right' : 'تحريك لليمين (+2px)',
                            onPressed: () {
                              final val = (currentDx + 2.0).clamp(-180.0, 180.0);
                              setSheetState(() => cfg.dx = val);
                              setState(() {});
                              _saveCurrentLayout();
                            },
                          ),
                        ],
                      ),

                      // Quick Horizontal Alignment Presets
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _buildPresetChip(
                              label: _isEnglish ? '⬅️ Far Left' : '⬅️ أقصى اليسار',
                              isSelected: currentDx <= -70,
                              onTap: () {
                                setSheetState(() => cfg.dx = -90.0);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildPresetChip(
                              label: _isEnglish ? '🎯 Center' : '🎯 توسيط الشعار (0)',
                              isSelected: currentDx == 0.0,
                              onTap: () {
                                setSheetState(() => cfg.dx = 0.0);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildPresetChip(
                              label: _isEnglish ? '➡️ Far Right' : '➡️ أقصى اليمين',
                              isSelected: currentDx >= 70,
                              onTap: () {
                                setSheetState(() => cfg.dx = 90.0);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 3. Vertical Movement (Up / Down)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.swap_vert_rounded, color: Color(0xFF10B981), size: 20),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _isEnglish ? 'Move Up / Down (Vertical):' : 'التحريك لأعلى ولأسفل (رأسياً):',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF10B981), width: 1),
                            ),
                            child: Text(
                              currentDy == 0.0
                                  ? (_isEnglish ? 'Center (0)' : 'افتراضي (0)')
                                  : (currentDy > 0
                                      ? (_isEnglish ? 'Down +${currentDy.toInt()}px' : 'أسفل +${currentDy.toInt()}px')
                                      : (_isEnglish ? 'Up ${currentDy.toInt()}px' : 'أعلى ${currentDy.toInt()}px')),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white70, size: 22),
                            tooltip: _isEnglish ? 'Move Up' : 'تحريك لأعلى (-2px)',
                            onPressed: () {
                              final val = (currentDy - 2.0).clamp(-80.0, 80.0);
                              setSheetState(() => cfg.dy = val);
                              setState(() {});
                              _saveCurrentLayout();
                            },
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFF10B981),
                                inactiveTrackColor: const Color(0xFF334155),
                                thumbColor: const Color(0xFF10B981),
                                overlayColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: currentDy.clamp(-80.0, 80.0),
                                min: -80.0,
                                max: 80.0,
                                divisions: 80,
                                onChanged: (val) {
                                  setSheetState(() => cfg.dy = val);
                                  setState(() {});
                                  _saveCurrentLayout();
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward_rounded, color: Colors.white70, size: 22),
                            tooltip: _isEnglish ? 'Move Down' : 'تحريك لأسفل (+2px)',
                            onPressed: () {
                              final val = (currentDy + 2.0).clamp(-80.0, 80.0);
                              setSheetState(() => cfg.dy = val);
                              setState(() {});
                              _saveCurrentLayout();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Re-crop or Reset buttons row
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF00F2FE)),
                                foregroundColor: const Color(0xFF00F2FE),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.crop_rounded, size: 16),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _isEnglish ? 'Re-crop in Circle ✂️' : 'إعادة قص الصورة بالدائرة ✂️',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                if (isBottomSeal) {
                                  _recropOfficialLogo();
                                } else {
                                  _recropCertificateTopImage();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orangeAccent,
                                side: const BorderSide(color: Colors.orangeAccent),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _isEnglish ? 'Reset Position' : 'إعادة ضبط الموقع',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                              onPressed: () {
                                setSheetState(() {
                                  cfg.scale = 1.0;
                                  cfg.dx = 0.0;
                                  cfg.dy = 0.0;
                                });
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Open bottom sheet to edit certificate text content, font family, font size, and font color
  void _showTextAndFontEditor({CertificateElementType? initialType}) {
    CertificateElementType selectedType = initialType ?? CertificateElementType.title;
    final TextEditingController textCtrl = TextEditingController();

    String getCurrentText(CertificateElementType type) {
      switch (type) {
        case CertificateElementType.title:
          return _effCertTitle;
        case CertificateElementType.studentName:
          return _effStudentName;
        case CertificateElementType.reason:
          return _effReason;
        case CertificateElementType.rankBadge:
          return _effRankText;
        case CertificateElementType.signatureRight:
          return _effTeacherName;
        case CertificateElementType.signatureLeft:
          return _effDate;
        case CertificateElementType.logo:
          return _isEnglish ? 'Top Logo' : 'الشعار العلوي';
        default:
          return '';
      }
    }

    void updateCurrentText(CertificateElementType type, String value) {
      setState(() {
        switch (type) {
          case CertificateElementType.title:
            _customCertTitle = value;
            if (_isEnglish) {
              _tierTitlesEn[_currentTier] = value;
            } else {
              _tierTitlesAr[_currentTier] = value;
            }
            break;
          case CertificateElementType.studentName:
            _customStudentName = value;
            break;
          case CertificateElementType.reason:
            _customReasonText = value;
            if (_isEnglish) {
              _tierReasonsEn[_currentTier] = value;
            } else {
              _tierReasonsAr[_currentTier] = value;
            }
            break;
          case CertificateElementType.rankBadge:
            _customRankText = value;
            break;
          case CertificateElementType.signatureRight:
            _customTeacherName = value;
            _teacherName = value;
            break;
          case CertificateElementType.signatureLeft:
            _customDate = value;
            break;
          default:
            break;
        }
      });
      _saveTierSettings(_currentTier);
      if (type == CertificateElementType.signatureRight) {
        widget.database.setSetting('teacher_name', value);
      }
    }

    textCtrl.text = getCurrentText(selectedType);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cfg = _currentLayout.getConfig(selectedType);

            final List<Map<String, String>> fontFamilies = [
              {'id': 'Cairo', 'name': 'كايرو (Cairo)'},
              {'id': 'serif', 'name': 'نسخي كلاسيكي (Serif)'},
              {'id': 'sans-serif', 'name': 'رقمي حديث (Sans)'},
              {'id': 'monospace', 'name': 'مستقيم (Mono)'},
            ];

            final List<int> palette = [
              0xFFFFD700, // ذهبي ساطع
              0xFFD4AF37, // ذهبي ملكي
              0xFFFFFFFF, // أبيض ناصع
              0xFF00F2FE, // سماوي نيون
              0xFF10B981, // أخضر زمردي
              0xFFF59E0B, // برتقالي كهرماني
              0xFFEF4444, // أحمر ياقوتي
              0xFF1E3A8A, // كحلي كلاسيكي
              0xFF111827, // أسود داكن
              0xFFA855F7, // بنفسجي ملكي
            ];

            final currentFont = cfg.fontFamily.isNotEmpty ? cfg.fontFamily : 'Cairo';
            final currentSize = cfg.fontSize > 0 ? cfg.fontSize : 16.0;
            final currentColorVal = cfg.colorValue != 0 ? cfg.colorValue : 0xFFFFD700;
            final isBold = cfg.fontWeightIndex >= 4;

            final availableElements = [
              CertificateElementType.logo,
              CertificateElementType.seal,
              CertificateElementType.title,
              CertificateElementType.studentName,
              CertificateElementType.reason,
              CertificateElementType.rankBadge,
              CertificateElementType.signatureRight,
              CertificateElementType.signatureLeft,
            ];

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 14,
                left: 16,
                right: 16,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Text('✍️', style: TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _isEnglish ? 'Edit Texts & Font Styling' : 'تعديل نصوص وخطوط الشهادة',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      _isEnglish ? 'Changes preview live and preserve certificate size' : 'تعديل النص والخط واللون مع الحفاظ على أبعاد الشهادة',
                                      style: const TextStyle(fontSize: 9.5, color: Colors.white54),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                          onPressed: () => Navigator.pop(bottomSheetContext),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 16),

                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: availableElements.map((el) {
                          final isSel = el == selectedType;
                          return Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              label: Text(
                                '${el.iconStr} ${_isEnglish ? el.displayNameEn : el.displayNameAr}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  color: isSel ? Colors.black : Colors.white70,
                                ),
                              ),
                              selected: isSel,
                              selectedColor: const Color(0xFF00F2FE),
                              backgroundColor: const Color(0xFF0F172A),
                              onSelected: (val) {
                                if (val) {
                                  setSheetState(() {
                                    selectedType = el;
                                    textCtrl.text = getCurrentText(el);
                                  });
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (selectedType == CertificateElementType.logo || selectedType == CertificateElementType.seal) ...[
                      // 1. Logo / Seal Size / Scale Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.aspect_ratio_rounded, color: Color(0xFFFBBF24), size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    selectedType == CertificateElementType.seal
                                        ? (_isEnglish ? 'Seal Size / Scale:' : 'حجم وتكبير الختم السفلي:')
                                        : (_isEnglish ? 'Logo Size / Scale:' : 'حجم وتكبير الشعار العلوي:'),
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFBBF24), width: 1),
                            ),
                            child: Text(
                              '${(cfg.scale * 100).toInt()}%',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFFBBF24)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white70, size: 24),
                            onPressed: cfg.scale > 0.4
                                ? () {
                                    final val = (cfg.scale - 0.05).clamp(0.4, 2.5);
                                    setSheetState(() => cfg.scale = val);
                                    setState(() {});
                                    _saveCurrentLayout();
                                  }
                                : null,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFFFBBF24),
                                inactiveTrackColor: const Color(0xFF334155),
                                thumbColor: const Color(0xFFFBBF24),
                                overlayColor: const Color(0xFFFBBF24).withValues(alpha: 0.2),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: cfg.scale.clamp(0.4, 2.5),
                                min: 0.4,
                                max: 2.5,
                                divisions: 42,
                                onChanged: (val) {
                                  setSheetState(() => cfg.scale = val);
                                  setState(() {});
                                  _saveCurrentLayout();
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70, size: 24),
                            onPressed: cfg.scale < 2.5
                                ? () {
                                    final val = (cfg.scale + 0.05).clamp(0.4, 2.5);
                                    setSheetState(() => cfg.scale = val);
                                    setState(() {});
                                    _saveCurrentLayout();
                                  }
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 2. Move Left / Right Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.swap_horiz_rounded, color: Color(0xFF00F2FE), size: 20),
                              const SizedBox(width: 6),
                              Text(
                                _isEnglish ? 'Move Left / Right:' : 'التحريك يميناً ويساراً (أفقياً):',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF00F2FE), width: 1),
                            ),
                            child: Text(
                              cfg.dx == 0.0
                                  ? (_isEnglish ? 'Center (0)' : 'المنتصف (0)')
                                  : (cfg.dx > 0
                                      ? (_isEnglish ? 'Right +${cfg.dx.toInt()}px' : 'يمين +${cfg.dx.toInt()}px')
                                      : (_isEnglish ? 'Left ${cfg.dx.toInt()}px' : 'يسار ${cfg.dx.toInt()}px')),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF00F2FE)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 22),
                            onPressed: () {
                              final val = (cfg.dx - 5.0).clamp(-180.0, 180.0);
                              setSheetState(() => cfg.dx = val);
                              setState(() {});
                              _saveCurrentLayout();
                            },
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFF00F2FE),
                                inactiveTrackColor: const Color(0xFF334155),
                                thumbColor: const Color(0xFF00F2FE),
                                overlayColor: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: cfg.dx.clamp(-180.0, 180.0),
                                min: -180.0,
                                max: 180.0,
                                divisions: 72,
                                onChanged: (val) {
                                  setSheetState(() => cfg.dx = val);
                                  setState(() {});
                                  _saveCurrentLayout();
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 22),
                            onPressed: () {
                              final val = (cfg.dx + 5.0).clamp(-180.0, 180.0);
                              setSheetState(() => cfg.dx = val);
                              setState(() {});
                              _saveCurrentLayout();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 3. Move Up / Down Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.swap_vert_rounded, color: Color(0xFF10B981), size: 20),
                              const SizedBox(width: 6),
                              Text(
                                _isEnglish ? 'Move Up / Down:' : 'التحريك لأعلى ولأسفل (رأسياً):',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF10B981), width: 1),
                            ),
                            child: Text(
                              cfg.dy == 0.0
                                  ? (_isEnglish ? 'Default (0)' : 'افتراضي (0)')
                                  : (cfg.dy > 0
                                      ? (_isEnglish ? 'Down +${cfg.dy.toInt()}px' : 'أسفل +${cfg.dy.toInt()}px')
                                      : (_isEnglish ? 'Up ${cfg.dy.toInt()}px' : 'أعلى ${cfg.dy.toInt()}px')),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF10B981)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white70, size: 22),
                            onPressed: () {
                              final val = (cfg.dy - 4.0).clamp(-60.0, 60.0);
                              setSheetState(() => cfg.dy = val);
                              setState(() {});
                              _saveCurrentLayout();
                            },
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFF10B981),
                                inactiveTrackColor: const Color(0xFF334155),
                                thumbColor: const Color(0xFF10B981),
                                overlayColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: cfg.dy.clamp(-60.0, 60.0),
                                min: -60.0,
                                max: 60.0,
                                divisions: 30,
                                onChanged: (val) {
                                  setSheetState(() => cfg.dy = val);
                                  setState(() {});
                                  _saveCurrentLayout();
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward_rounded, color: Colors.white70, size: 22),
                            onPressed: () {
                              final val = (cfg.dy + 4.0).clamp(-60.0, 60.0);
                              setSheetState(() => cfg.dy = val);
                              setState(() {});
                              _saveCurrentLayout();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF00F2FE)),
                                foregroundColor: const Color(0xFF00F2FE),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.photo_library_rounded, size: 16),
                              label: Text(
                                selectedType == CertificateElementType.seal
                                    ? (_isEnglish ? 'Change Seal Picture' : 'تغيير صورة الختم')
                                    : (_isEnglish ? 'Change Picture' : 'اختيار صورة بديلة'),
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () {
                                Navigator.pop(bottomSheetContext);
                                if (selectedType == CertificateElementType.seal) {
                                  _pickOfficialLogo();
                                } else {
                                  _pickCertificateTopImage();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.orangeAccent),
                                foregroundColor: Colors.orangeAccent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: Text(_isEnglish ? 'Reset Position' : 'إعادة ضبط الموقع', style: const TextStyle(fontSize: 11)),
                              onPressed: () {
                                setSheetState(() {
                                  cfg.scale = 1.0;
                                  cfg.dx = 0.0;
                                  cfg.dy = 0.0;
                                });
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        _isEnglish ? 'Element Text:' : 'النص المكتوب في الشهادة:',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: textCtrl,
                        maxLines: selectedType == CertificateElementType.reason ? 3 : 1,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          hintText: _isEnglish ? 'Enter text...' : 'أدخل النص هنا...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF00F2FE)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (val) {
                          updateCurrentText(selectedType, val);
                        },
                      ),
                      const SizedBox(height: 14),

                      Text(
                        _isEnglish ? 'Font Family:' : 'نوع الخط (Font Family):',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: fontFamilies.map((f) {
                          final isSel = currentFont == f['id'];
                          return ChoiceChip(
                            label: Text(
                              f['name']!,
                              style: TextStyle(
                                fontFamily: f['id'],
                                fontSize: 11,
                                color: isSel ? Colors.black : Colors.white70,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            selected: isSel,
                            selectedColor: const Color(0xFFFBBF24),
                            backgroundColor: const Color(0xFF0F172A),
                            onSelected: (val) {
                              if (val) {
                                setSheetState(() {
                                  cfg.fontFamily = f['id']!;
                                });
                                setState(() {});
                                _saveCurrentLayout();
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isEnglish ? 'Font Size:' : 'حجم الخط (Font Size):',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Text(
                              '${currentSize.toStringAsFixed(1)} pt',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24)),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white70, size: 22),
                            onPressed: currentSize > 7
                                ? () {
                                    final n = (currentSize - 1.0).clamp(7.0, 34.0);
                                    setSheetState(() => cfg.fontSize = n);
                                    setState(() {});
                                    _saveCurrentLayout();
                                  }
                                : null,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFF00F2FE),
                                inactiveTrackColor: const Color(0xFF334155),
                                thumbColor: const Color(0xFF00F2FE),
                                overlayColor: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                                trackHeight: 3.5,
                              ),
                              child: Slider(
                                value: currentSize.clamp(7.0, 34.0),
                                min: 7.0,
                                max: 34.0,
                                divisions: 54,
                                onChanged: (val) {
                                  setSheetState(() => cfg.fontSize = val);
                                  setState(() {});
                                  _saveCurrentLayout();
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white70, size: 22),
                            onPressed: currentSize < 34
                                ? () {
                                    final n = (currentSize + 1.0).clamp(7.0, 34.0);
                                    setSheetState(() => cfg.fontSize = n);
                                    setState(() {});
                                    _saveCurrentLayout();
                                  }
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Text(
                        _isEnglish ? 'Font Color:' : 'لون الخط (Font Color):',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: palette.map((c) {
                          final isSel = currentColorVal == c;
                          return InkWell(
                            onTap: () {
                              setSheetState(() => cfg.colorValue = c);
                              setState(() {});
                              _saveCurrentLayout();
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(c),
                                border: Border.all(
                                  color: isSel ? Colors.white : Colors.black26,
                                  width: isSel ? 3 : 1,
                                ),
                                boxShadow: isSel
                                    ? [BoxShadow(color: Color(c).withValues(alpha: 0.7), blurRadius: 8)]
                                    : null,
                              ),
                              child: isSel
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: (c == 0xFFFFFFFF || c == 0xFFFFD700 || c == 0xFF00F2FE) ? Colors.black : Colors.white,
                                    )
                                : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('B عريض', style: TextStyle(fontSize: 11)),
                              selected: isBold,
                              selectedColor: const Color(0xFFFBBF24),
                              backgroundColor: const Color(0xFF0F172A),
                              labelStyle: TextStyle(
                                color: isBold ? Colors.black : Colors.white70,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (val) {
                                setSheetState(() => cfg.fontWeightIndex = val ? 5 : 2);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('I مائل', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                              selected: cfg.isItalic,
                              selectedColor: const Color(0xFFFBBF24),
                              backgroundColor: const Color(0xFF0F172A),
                              labelStyle: TextStyle(
                                color: cfg.isItalic ? Colors.black : Colors.white70,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (val) {
                                setSheetState(() => cfg.isItalic = val);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('U تسطير', style: TextStyle(fontSize: 11, decoration: TextDecoration.underline)),
                              selected: cfg.isUnderline,
                              selectedColor: const Color(0xFFFBBF24),
                              backgroundColor: const Color(0xFF0F172A),
                              labelStyle: TextStyle(
                                color: cfg.isUnderline ? Colors.black : Colors.white70,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (val) {
                                setSheetState(() => cfg.isUnderline = val);
                                setState(() {});
                                _saveCurrentLayout();
                              },
                            ),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              icon: const Icon(Icons.refresh_rounded, size: 14, color: Colors.orangeAccent),
                              label: Text(
                                _isEnglish ? 'Reset' : 'استعادة الأصل',
                                style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
                              ),
                              onPressed: () {
                              final defLayout = CertificateTierLayout.defaultFor(_currentTier, _selectedStyle);
                              final defCfg = defLayout.getConfig(selectedType);
                              setSheetState(() {
                                cfg.fontFamily = defCfg.fontFamily;
                                cfg.fontSize = defCfg.fontSize;
                                cfg.colorValue = defCfg.colorValue;
                                cfg.fontWeightIndex = defCfg.fontWeightIndex;
                                cfg.isItalic = defCfg.isItalic;
                                cfg.isUnderline = defCfg.isUnderline;
                                switch (selectedType) {
                                  case CertificateElementType.title:
                                    _customCertTitle = null;
                                    break;
                                  case CertificateElementType.studentName:
                                    _customStudentName = null;
                                    break;
                                  case CertificateElementType.reason:
                                    _customReasonText = null;
                                    break;
                                  case CertificateElementType.rankBadge:
                                    _customRankText = null;
                                    break;
                                  case CertificateElementType.signatureRight:
                                    _customTeacherName = null;
                                    break;
                                  case CertificateElementType.signatureLeft:
                                    _customDate = null;
                                    break;
                                  default:
                                    break;
                                }
                                textCtrl.text = getCurrentText(selectedType);
                              });
                              setState(() {});
                              _saveCurrentLayout();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPresetChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00F2FE).withValues(alpha: 0.2) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF00F2FE) : const Color(0xFF334155),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
            color: isSelected ? const Color(0xFF00F2FE) : Colors.white70,
          ),
        ),
      ),
    );
  }

  /// Official System Logo Image helper (loads file or asset)
  Widget _buildOfficialLogoImage({double size = 32}) {
    final hasCustom = _customLogoPath.isNotEmpty && File(_customLogoPath).existsSync();
    if (hasCustom) {
      return Image.file(
        File(_customLogoPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/images/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
        ),
      );
    }
    return Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
    );
  }

  /// Certificate Top Custom Picture (Selected by user from gallery with circular cropper)
  Widget _buildCertificateTopImage({double size = 54, Color? borderColor}) {
    final hasCustom = _certCustomImagePath.isNotEmpty && File(_certCustomImagePath).existsSync();
    final border = borderColor ?? const Color(0xFFD4AF37);

    return Tooltip(
      message: _isEnglish
          ? 'Certificate Top Logo • Tap to change or crop'
          : 'لوجو الشهادة العلوي • اضغط للتعديل والتكبير والتحريك 🖼️',
      child: InkWell(
        onTap: _showTopImageOptions,
        onLongPress: () => _showLogoAdjustModal(isBottomSeal: false),
        borderRadius: BorderRadius.circular(size / 2),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: border, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: border.withValues(alpha: 0.4),
                    blurRadius: 7,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              // Zero padding ensures the cropped circular logo fits edge-to-edge with 100% pixel accuracy
              child: hasCustom
                  ? Image.file(
                      File(_certCustomImagePath),
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildDefaultCertTopEmblem(size, border),
                    )
                  : _buildDefaultCertTopEmblem(size, border),
            ),
            Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  shape: BoxShape.circle,
                  border: Border.all(color: border, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4),
                  ],
                ),
                child: Icon(
                  hasCustom ? Icons.crop_rotate_rounded : Icons.add_a_photo_rounded,
                  size: 11,
                  color: border,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultCertTopEmblem(double size, Color border) {
    // If the center has an official logo (the bottom logo), use it by default!
    if (_customLogoPath.isNotEmpty && File(_customLogoPath).existsSync()) {
      return Image.file(
        File(_customLogoPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.workspace_premium_rounded,
            color: border,
            size: size * 0.58,
          ),
        ),
      );
    }
    return Center(
      child: Icon(
        Icons.workspace_premium_rounded,
        color: border,
        size: size * 0.58,
      ),
    );
  }

  /// Capture Certificate widget as ultra-HD PNG bytes (exact dimensions and styling)
  Future<Uint8List?> _captureCertificateBytes() async {
    try {
      final boundary = _certKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      // إذا تجاوز الحجم 700KB، نستخدم نسبة 2.0 لحماية حد 1MB للوثيقة في Firestore مع الحفاظ على أعلى دقة
      if (byteData.lengthInBytes > 700000) {
        image = await boundary.toImage(pixelRatio: 2.0);
        byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      }

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error capturing certificate bytes: $e');
      return null;
    }
  }

  /// إصدار ونشر نفس صورة الشهادة بنفس الحجم الأصلي في برنامج المعلم لتطبيق الطالب
  Future<bool> _issueCertificateToStudentApp({bool showSuccessSnack = true}) async {
    if (_effStudentName.trim().isEmpty) return false;
    HapticFeedback.mediumImpact();
    setState(() => _isGenerating = true);

    try {
      String studentId = '';
      if (_certMode == CertificateMode.examRankings && _studentsRanked.isNotEmpty && _selectedStudentIndex < _studentsRanked.length) {
        studentId = _studentsRanked[_selectedStudentIndex].id;
      } else if (_selectedStudent != null) {
        studentId = _selectedStudent!.id;
      } else if (_studentsRanked.isNotEmpty && _selectedStudentIndex < _studentsRanked.length) {
        studentId = _studentsRanked[_selectedStudentIndex].id;
      }

      if (studentId.isEmpty) {
        final allDbStudents = await widget.database.getStudents();
        final matched = allDbStudents.where((s) => s.fullName.trim() == _effStudentName.trim()).firstOrNull;
        if (matched != null) {
          studentId = matched.id;
        }
      }

      if (studentId.isEmpty) {
        if (mounted && showSuccessSnack) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('يرجى تحديد الطالب المراد إصدار شهادته أولاً'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }

      String examId = _selectedExam?.id ?? '';
      if (examId.isEmpty) {
        if (_exams.isNotEmpty) {
          examId = _exams.first.id;
        } else {
          examId = 'cert_${DateTime.now().millisecondsSinceEpoch}';
        }
      }
      final examTitle = _effExamTitle;
      final certTitle = _effCertTitle;

      final pngBytes = await _captureCertificateBytes();
      if (pngBytes == null) {
        if (mounted && showSuccessSnack) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isEnglish ? 'Failed to capture certificate image.' : 'تعذر التقاط صورة الشهادة، يرجى إعادة المحاولة.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return false;
      }

      final success = await CloudSyncService.instance.publishCertificateImage(
        examId: examId,
        studentId: studentId,
        imageBytes: pngBytes,
        studentName: _effStudentName,
        examTitle: examTitle,
        certTitle: certTitle,
      );

      if (mounted && showSuccessSnack) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isEnglish
                          ? 'Certificate for $_effStudentName issued and sent to Student App! 🎓✨'
                          : 'تم إرسال نفس صورة الشهادة بالحجم والتصميم الأصلي للطالب ($_effStudentName) بنجاح! 🎓✨',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(_isEnglish ? 'Failed to sync certificate to cloud.' : 'تعذر إرسال الشهادة، تأكد من الاتصال بالإنترنت.'),
            ),
          );
        }
      }
      return success;
    } catch (e) {
      debugPrint('Error issuing certificate to student app: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  /// إصدار ونشر شهادات جميع الطلاب المتفوقين في الامتحان دفعة واحدة لتطبيق الطالب
  Future<void> _issueAllCertificatesToStudentApp() async {
    if (_studentsRanked.isEmpty || _selectedExam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد شهادات طلاب متفوقين للإصدار في هذا الامتحان')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('نشر جميع الشهادات 🚀', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل تريد إصدار ونشر صور شهادات جميع الطلاب المتفوقين (${_studentsRanked.length} طالب) بنفس تصميم الشهادة الأصلي لتطبيق الطالب مباشرة؟',
          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.send_rounded, size: 16),
            onPressed: () => Navigator.pop(ctx, true),
            label: const Text('نشر الكل الآن 🎓', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isGenerating = true);
    int successCount = 0;
    final originalIndex = _selectedStudentIndex;

    for (int i = 0; i < _studentsRanked.length; i++) {
      if (!mounted) break;
      setState(() => _selectedStudentIndex = i);
      await Future.delayed(const Duration(milliseconds: 220));
      final res = await _issueCertificateToStudentApp(showSuccessSnack: false);
      if (res) successCount++;
    }

    if (mounted) {
      setState(() {
        _selectedStudentIndex = originalIndex;
        _isGenerating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('تم إصدار ونشر ($successCount) شهادة بنفس الحجم الأصلي في تطبيق الطالب بنجاح! 🎓✨'),
        ),
      );
    }
  }

  /// Capture Certificate widget as ultra-HD PNG image
  Future<File?> _captureCertificateFile(String studentName) async {
    try {
      final boundary = _certKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final cleanName = studentName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '_');
      final file = File('${tempDir.path}/Certificate_$cleanName.png');
      await file.writeAsBytes(pngBytes);
      return file;
    } catch (e) {
      debugPrint('Error capturing certificate: $e');
      return null;
    }
  }

  /// Share Image to WhatsApp or other apps
  Future<void> _shareCertificateImage({bool directWhatsApp = false}) async {
    if (_effStudentName.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _isGenerating = true);

    try {
      final currentStudent = _studentsRanked.isNotEmpty && _selectedStudentIndex < _studentsRanked.length
          ? _studentsRanked[_selectedStudentIndex]
          : null;
      final studentId = currentStudent?.id ?? '';
      final examKey = _selectedExam?.id ?? 'cert';

      if (directWhatsApp && studentId.isNotEmpty) {
        final alreadySent = await widget.database.isMessageSentStrict(
          studentId: studentId,
          category: 'certificate',
          contextKey: examKey,
        );
        if (alreadySent) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_isEnglish
                    ? 'Certificate was already sent for this student! 🎓✓ (Locked)'
                    : 'تم إرسال شهادة هذا الطالب مسبقاً بالفعل! 🎓✓ (مغلق منعاً للتكرار)'),
                backgroundColor: const Color(0xFF64748B),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }

      final file = await _captureCertificateFile(_effStudentName);

      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isEnglish ? 'Failed to generate certificate image. Please retry.' : 'تعذر توليد صورة الشهادة، يرجى المحاولة مجدداً.'),
            ),
          );
        }
        return;
      }

      final scoreStr = currentStudent?.score ?? '';
      final percentStr = currentStudent?.percent ?? '';
      final tier = _currentTier;

      final String message;
      if (_isEnglish) {
        String tierMention;
        if (_certMode == CertificateMode.examRankings && currentStudent != null) {
          switch (tier) {
            case RankTier.rank1:
              tierMention = '🏆 *claiming 1st Place (Top of Cohort)*';
              break;
            case RankTier.rank2:
              tierMention = '🥈 *achieving 2nd Place (Runner-Up)*';
              break;
            case RankTier.rank3:
              tierMention = '🥉 *achieving 3rd Place (Distinction)*';
              break;
            case RankTier.ranks4to10:
              tierMention = '🎖️ *achieving $_effRankText and joining the Top 10 Honor Roll*';
              break;
          }
        } else {
          tierMention = '🌟 *$_effRankText*';
        }

        final studentGroupName = _effGroupName;
        message =
            'Warm congratulations from *$_effCenterName*! 🌟🎓\n\n'
            'We are delighted to congratulate the parents of our distinguished student: *$_effStudentName*\n'
            'For $tierMention in *$_effExamTitle*' +
            (studentGroupName.isNotEmpty ? ' • Group: $studentGroupName' : '') +
            (scoreStr.isNotEmpty ? ' with score *($scoreStr)* ($percentStr).\n\n' : '.\n\n') +
            'Attached is the official Certificate of Achievement honoring their outstanding dedication. Wishing them continued excellence and success! 💐';
      } else {
        String tierMention;
        if (_certMode == CertificateMode.examRankings && currentStudent != null) {
          switch (tier) {
            case RankTier.rank1:
              tierMention = '🏆 *تربعه على عرش المركز الأول (صدارة المجموعة)*';
              break;
            case RankTier.rank2:
              tierMention = '🥈 *نيله المركز الثاني بجدارة واقتدار*';
              break;
            case RankTier.rank3:
              tierMention = '🥉 *إحرازه المركز الثالث وتألقه على منصة التتويج*';
              break;
            case RankTier.ranks4to10:
              tierMention = '🎖️ *حصوله على $_effRankText وانضمامه المستحق إلى لوحة شرف العشرة الأوائل*';
              break;
          }
        } else {
          tierMention = '🌟 *$_effRankText*';
        }

        final studentGroupName = _effGroupName;
        message =
            'تهانينا الحارة من إدارة *$_effCenterName*! 🌟🎓\n\n'
            'يسرنا أن نبارك لولي أمر الطالب المتميز: *$_effStudentName*\n'
            'لحصوله على $tierMention في *$_effExamTitle*' +
            (studentGroupName.isNotEmpty ? ' • مجموعة: $studentGroupName' : '') +
            (scoreStr.isNotEmpty ? ' بدرجة *($scoreStr)* بنسبة *($percentStr)*.\n\n' : '.\n\n') +
            'مرفق أعلاه شهادة التقدير الرسمية المعتمدة تكريماً له على هذا المجهود الرائع والمستمر. جعله الله ذخراً لكم وبارك في تفوقه! 💐';
      }

      final parentPhone = _effParentPhone;
      if (directWhatsApp && parentPhone.isNotEmpty) {
        try {
          Clipboard.setData(ClipboardData(text: parentPhone));
        } catch (_) {}
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              name: 'Certificate_${_effStudentName}.png',
              mimeType: 'image/png',
            ),
          ],
          text: message,
        ),
      );

      // ترحيل ونشر نفس صورة الشهادة تلقائياً لتطبيق الطالب عند المشاركة
      _issueCertificateToStudentApp(showSuccessSnack: false);

      if (directWhatsApp && studentId.isNotEmpty) {
        await widget.database.recordSentMessage(
          studentId: studentId,
          category: 'certificate',
          contextKey: examKey,
          phone: parentPhone,
          status: 'sent',
        );
        if (mounted) {
          setState(() {
            _sentCertStudentIds.add(studentId);
          });
        }
      }

      if (mounted) {
        final phoneNote = (directWhatsApp && parentPhone.isNotEmpty)
            ? (_isEnglish ? ' (Parent Phone: $parentPhone copied)' : ' (تم نسخ هاتف ولي الأمر: $parentPhone)')
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((_isEnglish ? 'Certificate shared successfully! 🎓✨' : 'تم توليد ومشاركة شهادة $_effStudentName بنجاح! 🎓✨') + phoneNote),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Share error: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentStudent = _studentsRanked.isNotEmpty ? _studentsRanked[_selectedStudentIndex] : null;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: _isEnglish ? 'Back' : 'رجوع',
                onPressed: widget.onBack,
              )
            : null,
        title: Row(
          children: [
            const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 24),
            const SizedBox(width: 8),
            Text(
              _isEnglish ? 'Official Certificates 🎓' : 'شهادات التقدير الرسمية 🎓',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF00F2FE)),
            tooltip: _isEnglish ? 'Publish All Cohort Certificates' : 'إصدار ونشر شهادات جميع الأوائل لتطبيق الطالب 🚀',
            onPressed: _isGenerating ? null : _issueAllCertificatesToStudentApp,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFFFBBF24)),
            tooltip: _isEnglish ? 'Share as Image' : 'مشاركة كصورة',
            onPressed: _isGenerating ? null : () => _shareCertificateImage(directWhatsApp: false),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)))
          : SingleChildScrollView(
              padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Language Switcher Bar (🇪🇬 العربية | 🇬🇧 English)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (_isEnglish) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _isEnglish = false;
                                  _resetCustomOverrides();
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                gradient: !_isEnglish
                                    ? const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF00F2FE)])
                                    : null,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('🇪🇬', style: TextStyle(fontSize: 15)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'اللغة العربية',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: !_isEnglish ? FontWeight.w900 : FontWeight.bold,
                                      color: !_isEnglish ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (!_isEnglish) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _isEnglish = true;
                                  _resetCustomOverrides();
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                gradient: _isEnglish
                                    ? const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF00F2FE)])
                                    : null,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('🇬🇧', style: TextStyle(fontSize: 15)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'English Language',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _isEnglish ? FontWeight.w900 : FontWeight.bold,
                                      color: _isEnglish ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2. Mode Selector Bar (3 Modes: Exam Top | Group Student | Custom Free)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        _buildModeTab(
                          title: _isEnglish ? 'Exam Top 🏆' : 'أوائل الاختبارات 🏆',
                          mode: CertificateMode.examRankings,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 4),
                        _buildModeTab(
                          title: _isEnglish ? 'Group Student 👥' : 'تكريم بالمجموعة 👥',
                          mode: CertificateMode.groupStudent,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 4),
                        _buildModeTab(
                          title: _isEnglish ? 'Custom ✍️' : 'شهادة حرة ✍️',
                          mode: CertificateMode.customFree,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. Mode-Specific Controls Card
                  if (_certMode == CertificateMode.examRankings) ...[
                    // Exam selector bar (if exams exist)
                    if (_exams.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.quiz_rounded, color: Color(0xFF00F2FE), size: 18),
                            const SizedBox(width: 8),
                            Text(_isEnglish ? 'Exam:' : 'الاختبار:', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<ExamModel>(
                                  value: _selectedExam,
                                  isExpanded: true,
                                  items: _exams
                                      .map((e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(
                                              e.title,
                                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedExam = val);
                                      _loadStudentsForExam(val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    if (_studentsRanked.isEmpty && _customStudentName == null) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.assignment_late_rounded, size: 44, color: Colors.amber),
                            const SizedBox(height: 10),
                            Text(
                              _isEnglish ? 'No graded students found for this exam' : 'لا توجد درجات مرصودة لهذا الاختبار بعد',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isEnglish
                                  ? 'You can easily issue certificates by selecting a student from any group or creating a custom certificate directly below:'
                                  : 'يمكنك إصدار الشهادات فوراً باختيار طالب من أي مجموعة أو إنشاء شهادة حرة مخصصة بدون انتظار رصد الاختبار:',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black54, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0284C7),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  icon: const Icon(Icons.people_rounded, size: 16),
                                  label: Text(_isEnglish ? 'Honor Student by Group' : 'تكريم طالب من مجموعة 👥', style: const TextStyle(fontSize: 11.5)),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _certMode = CertificateMode.groupStudent);
                                  },
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF00F2FE),
                                    side: const BorderSide(color: Color(0xFF00F2FE)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                                  label: Text(_isEnglish ? 'Custom Free Certificate' : 'شهادة حرة مخصصة ✍️', style: const TextStyle(fontSize: 11.5)),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _certMode = CertificateMode.customFree);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Rank Tiers Allocation Cards (1st, 2nd, 3rd, and 4-10 Unified)
                      _buildTierSelectorRow(isDark),
                      const SizedBox(height: 14),

                      // Ranked Students Chips
                      Row(
                        children: [
                          const Icon(Icons.military_tech_rounded, color: Color(0xFFFBBF24), size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _isEnglish
                                ? 'Top Students (${_studentsRanked.length}) 🏆:'
                                : 'الطلاب المتفوقين (${_studentsRanked.length}) 🏆:',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      if (_studentsRanked.isNotEmpty)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: List.generate(_studentsRanked.length, (index) {
                              final s = _studentsRanked[index];
                              final isSel = index == _selectedStudentIndex;
                              final isRank4 = s.rank == 4;

                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isRank4) ...[
                                    Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.link_rounded, size: 12, color: Color(0xFF00F2FE)),
                                          const SizedBox(width: 4),
                                          Text(
                                            _isEnglish ? 'Unified (4-10)' : 'شهادة موحدة (4-10)',
                                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: InkWell(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _selectedStudentIndex = index;
                                          if (s.rank == 1) {
                                            _activeTier = RankTier.rank1;
                                          } else if (s.rank == 2) {
                                            _activeTier = RankTier.rank2;
                                          } else if (s.rank == 3) {
                                            _activeTier = RankTier.rank3;
                                          } else {
                                            _activeTier = RankTier.ranks4to10;
                                          }
                                          _resetCustomOverrides();
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          gradient: isSel
                                              ? const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF00F2FE)])
                                              : null,
                                          color: isSel ? null : (isDark ? const Color(0xFF1E293B) : Colors.white),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSel ? Colors.transparent : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                          ),
                                          boxShadow: isSel
                                              ? [BoxShadow(color: const Color(0xFF00F2FE).withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))]
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 9,
                                              backgroundColor: s.rank == 1
                                                  ? const Color(0xFFFBBF24)
                                                  : (s.rank == 2 ? const Color(0xFF94A3B8) : (s.rank == 3 ? const Color(0xFFB45309) : Colors.grey)),
                                              child: Text(
                                                '${s.rank}',
                                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              s.name.split(' ').take(2).join(' '),
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                                                color: isSel ? Colors.black : (isDark ? Colors.white : Colors.black87),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '(${s.score})',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                color: isSel ? Colors.black87 : const Color(0xFF10B981),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (_sentCertStudentIds.contains(s.id)) ...[
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.check_circle_rounded,
                                                size: 13,
                                                color: isSel ? Colors.black87 : const Color(0xFF10B981),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                    ],
                  ] else if (_certMode == CertificateMode.groupStudent) ...[
                    _buildGroupStudentControls(isDark),
                  ] else ...[
                    _buildCustomFreeControls(isDark),
                  ],
                  const SizedBox(height: 14),

                  // 4. Style Selector Cards (Bound to the Active Tier!)
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00F2FE), size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _certMode == CertificateMode.examRankings
                              ? (_isEnglish
                                  ? 'Style for ${_getTierDisplayName(_currentTier, true)} 🎨:'
                                  : 'اختر قالب (${_getTierDisplayName(_currentTier, false)}) 🎨:')
                              : (_isEnglish ? 'Choose Certificate Luxury Style 🎨:' : 'اختر قالب وتصميم الشهادة الفاخر 🎨:'),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStyleCard(
                          title: _isEnglish ? 'Royal Gold' : 'الذهبي الملكي',
                          sub: _isEnglish ? 'Imperial Crest' : 'تاج وتطريز ملكي',
                          icon: '👑',
                          style: CertificateStyle.royal,
                          accentColor: const Color(0xFFD4AF37),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStyleCard(
                          title: _isEnglish ? 'Diploma' : 'الدبلوم الرسمي',
                          sub: _isEnglish ? 'Parchment & Seal' : 'عاجي + ختم شمعي',
                          icon: '🏛️',
                          style: CertificateStyle.classic,
                          accentColor: const Color(0xFF1E3A8A),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStyleCard(
                          title: _isEnglish ? 'Nature Wood' : 'الخشبي الطبيعي',
                          sub: _isEnglish ? 'Wood & Laurel' : 'خشب وأغصان غار',
                          icon: '🌿',
                          style: CertificateStyle.natureWood,
                          accentColor: const Color(0xFF22C55E),
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Dual Logo Actions (Top Logo & Official Center/Bottom Logo)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                            side: BorderSide(color: const Color(0xFFD4AF37).withValues(alpha: 0.8), width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            backgroundColor: const Color(0xFFD4AF37).withValues(alpha: 0.08),
                          ),
                          icon: const Icon(Icons.add_photo_alternate_rounded, size: 16, color: Color(0xFFD4AF37)),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isEnglish ? 'Top Logo 🖼️' : 'اللوجو العلوي 🖼️',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37)),
                            ),
                          ),
                          onPressed: _showTopImageOptions,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                            side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.8), width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.08),
                          ),
                          icon: const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF10B981)),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isEnglish ? 'Center Logo 🏫' : 'لوجو السنتر (السفلي) 🏫',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                            ),
                          ),
                          onPressed: _showOfficialLogoOptions,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.edit_note_rounded, size: 20),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _isEnglish ? 'Edit Texts & Font Styling ✍️' : 'تعديل نصوص وخطوط الشهادة (نوع، حجم، لون) ✍️',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    onPressed: () => _showTextAndFontEditor(),
                  ),
                  const SizedBox(height: 12),

                  // 5. Live Certificate Canvas (Captured via RepaintBoundary)
                  Center(
                    child: RepaintBoundary(
                      key: _certKey,
                      child: Directionality(
                        textDirection: _isEnglish ? TextDirection.ltr : TextDirection.rtl,
                        child: _buildCertificateCanvas(currentStudent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6. Action Buttons (Direct to Student App, WhatsApp, & PNG save)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 3,
                    ),
                    icon: _isGenerating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload_rounded, size: 20),
                    label: Text(
                      _isEnglish ? 'Issue & Send to Student App 🎓' : 'اعتماد وإرسال الشهادة لتطبيق الطالب 🎓📲',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    onPressed: _isGenerating ? null : () => _issueCertificateToStudentApp(),
                  ),
                  const SizedBox(height: 8),

                  Builder(
                    builder: (ctx) {
                      final isCertAlreadySent = currentStudent != null &&
                          currentStudent.id.isNotEmpty &&
                          _sentCertStudentIds.contains(currentStudent.id);

                      return FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: isCertAlreadySent
                              ? (isDark ? Colors.grey.shade800 : Colors.grey.shade300)
                              : const Color(0xFF25D366),
                          foregroundColor: isCertAlreadySent
                              ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
                              : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: isCertAlreadySent ? 0 : 3,
                        ),
                        icon: _isGenerating
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(isCertAlreadySent ? Icons.check_circle_rounded : Icons.send_rounded, size: 20),
                        label: Text(
                          _isGenerating
                              ? (_isEnglish ? 'Exporting and sharing...' : 'جارٍ تصدير ومشاركة الشهادة...')
                              : (isCertAlreadySent
                                  ? (_isEnglish ? 'Certificate Already Sent ✓' : 'تم إرسال الشهادة بالفعل ✓ (مغلق)')
                                  : (_isEnglish ? 'Send Certificate via WhatsApp 📲' : 'إرسال الشهادة لولي الأمر عبر واتساب 📲')),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        onPressed: _isGenerating || isCertAlreadySent ? null : () => _shareCertificateImage(directWhatsApp: true),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00F2FE)),
                      foregroundColor: const Color(0xFF00F2FE),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: Text(
                      _isEnglish ? 'Save & Share Ultra-HD PNG 📥' : 'حفظ ومشاركة كصورة عالية الدقة (Ultra-HD PNG) 📥',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _isGenerating ? null : () => _shareCertificateImage(directWhatsApp: false),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildModeTab({
    required String title,
    required CertificateMode mode,
    required bool isDark,
  }) {
    final isSel = _certMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (_certMode != mode) {
            HapticFeedback.selectionClick();
            setState(() {
              _certMode = mode;
              _resetCustomOverrides();
            });
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            gradient: isSel
                ? const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF00F2FE)])
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
              color: isSel ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupStudentControls(bool isDark) {
    final currentGroupStudents = _selectedGroup != null ? (_groupStudentsMap[_selectedGroup!.id] ?? []) : <StudentModel>[];
    final presets = _isEnglish ? _commendationPresetsEn : _commendationPresetsAr;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, color: Color(0xFF00F2FE), size: 18),
              const SizedBox(width: 6),
              Text(
                _isEnglish ? 'Select Group & Student 👥:' : 'اختيار المجموعة والطالب 👥:',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Group and Student Pickers
          Row(
            children: [
              // Group dropdown
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<GroupModel>(
                      value: _selectedGroup,
                      isExpanded: true,
                      hint: Text(_isEnglish ? 'Select Group' : 'المجموعة'),
                      items: _groups.map((g) => DropdownMenuItem(
                        value: g,
                        child: Text(g.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedGroup = val;
                            final list = _groupStudentsMap[val.id] ?? [];
                            _selectedStudent = list.isNotEmpty ? list.first : null;
                            _resetCustomOverrides();
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Student dropdown
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<StudentModel>(
                      value: currentGroupStudents.contains(_selectedStudent) ? _selectedStudent : null,
                      isExpanded: true,
                      hint: Text(_isEnglish ? 'Select Student' : 'اسم الطالب'),
                      items: currentGroupStudents.map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.fullName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedStudent = val;
                            _resetCustomOverrides();
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Commendation Presets
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 16),
              const SizedBox(width: 6),
              Text(
                _isEnglish ? 'Preset Commendation & Honor Title:' : 'وسام ومناسبة التكريم المعتمدة:',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: presets.map((p) {
                final isSel = _selectedPresetRank == p['rank'];
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(p['title'] ?? ''),
                    selected: isSel,
                    selectedColor: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                    side: BorderSide(
                      color: isSel ? const Color(0xFF00F2FE) : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                    ),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                      color: isSel ? const Color(0xFF00F2FE) : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    onSelected: (val) {
                      if (val) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedPresetRank = p['rank'] ?? '';
                          _selectedPresetReason = p['reason'] ?? '';
                          _resetCustomOverrides();
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomFreeControls(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: Color(0xFF00F2FE), size: 18),
              const SizedBox(width: 6),
              Text(
                _isEnglish ? 'Custom Certificate Details ✍️:' : 'بيانات الشهادة الحرة المخصصة ✍️:',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Student Name
          TextField(
            controller: _customFreeStudentCtrl,
            decoration: InputDecoration(
              isDense: true,
              labelText: _isEnglish ? 'Student / Honoree Name' : 'اسم الطالب أو المكرم',
              hintText: _isEnglish ? 'e.g. John Doe' : 'مثال: أحمد محمد علي',
              prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            style: const TextStyle(fontSize: 12.5),
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              // Occasion / Subject
              Expanded(
                child: TextField(
                  controller: _customFreeOccasionCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: _isEnglish ? 'Occasion / Subject' : 'المناسبة أو المادة',
                    hintText: _isEnglish ? 'e.g. Science Fair' : 'مثال: ختام الأنشطة / تكنولوجيا',
                    prefixIcon: const Icon(Icons.event_note_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (val) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),

              // Rank / Honor Title
              Expanded(
                child: TextField(
                  controller: _customFreeRankCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: _isEnglish ? 'Award / Rank Title' : 'الرتبة أو مسمى الوسام',
                    hintText: _isEnglish ? 'e.g. 1st Place' : 'مثال: وسام التميز والإبداع',
                    prefixIcon: const Icon(Icons.military_tech_outlined, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (val) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Commendation Reason
          TextField(
            controller: _customFreeReasonCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              isDense: true,
              labelText: _isEnglish ? 'Commendation Text' : 'نص الإشادة والتقدير',
              hintText: _isEnglish ? 'Reason or commendation wording...' : 'عبارة التقدير المكتوبة على متن الشهادة...',
              prefixIcon: const Icon(Icons.format_quote_rounded, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 8),

          // Parent WhatsApp Phone
          TextField(
            controller: _customFreePhoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              isDense: true,
              labelText: _isEnglish ? 'Parent Phone (WhatsApp)' : 'رقم هاتف ولي الأمر (واتساب)',
              hintText: _isEnglish ? 'e.g. 01012345678' : 'مثال: 01012345678',
              prefixIcon: const Icon(Icons.phone_outlined, size: 18, color: Color(0xFF25D366)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (val) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard({
    required RankTier tier,
    required String title,
    required String subtitle,
    required String icon,
    required Color accentColor,
    required bool isDark,
    String? badgeTag,
  }) {
    final isSel = _currentTier == tier;
    final studentCount = _studentsRanked.where((s) {
      if (tier == RankTier.rank1) return s.rank == 1;
      if (tier == RankTier.rank2) return s.rank == 2;
      if (tier == RankTier.rank3) return s.rank == 3;
      return s.rank >= 4;
    }).length;

    return InkWell(
      onTap: () => _selectTier(tier),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 126,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSel
              ? accentColor.withValues(alpha: 0.16)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSel ? accentColor : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            width: isSel ? 2.2 : 1,
          ),
          boxShadow: isSel
              ? [BoxShadow(color: accentColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(icon, style: const TextStyle(fontSize: 18)),
                if (badgeTag != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF00F2FE), width: 0.8),
                    ),
                    child: Text(
                      badgeTag,
                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                color: isSel ? (isDark ? Colors.white : Colors.black) : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ),
            if (studentCount > 0) ...[
              const SizedBox(height: 2),
              Text(
                _isEnglish ? '$studentCount student(s)' : '($studentCount طالب)',
                style: TextStyle(fontSize: 8, color: isDark ? Colors.white38 : Colors.black45),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTierSelectorRow(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.stars_rounded, color: Color(0xFFFBBF24), size: 19),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _isEnglish
                    ? 'Certificate Allocation (Top 3 Distinct + Unified 4-10) 🏆:'
                    : 'تخصيص شهادات المراتب (الأول، الثاني، الثالث، والمراكز 4-10) 🏆:',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildTierCard(
                tier: RankTier.rank1,
                title: _isEnglish ? '1st Place' : 'المركز الأول',
                subtitle: _getStyleName(_tierStyles[RankTier.rank1]!, _isEnglish),
                icon: '🥇',
                accentColor: const Color(0xFFFBBF24),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildTierCard(
                tier: RankTier.rank2,
                title: _isEnglish ? '2nd Place' : 'المركز الثاني',
                subtitle: _getStyleName(_tierStyles[RankTier.rank2]!, _isEnglish),
                icon: '🥈',
                accentColor: const Color(0xFF94A3B8),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildTierCard(
                tier: RankTier.rank3,
                title: _isEnglish ? '3rd Place' : 'المركز الثالث',
                subtitle: _getStyleName(_tierStyles[RankTier.rank3]!, _isEnglish),
                icon: '🥉',
                accentColor: const Color(0xFFB45309),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildTierCard(
                tier: RankTier.ranks4to10,
                title: _isEnglish ? 'Ranks 4 - 10' : 'المراكز 4 - 10',
                subtitle: _getStyleName(_tierStyles[RankTier.ranks4to10]!, _isEnglish),
                badgeTag: _isEnglish ? 'Unified' : 'شهادة موحدة',
                icon: '🎖️',
                accentColor: const Color(0xFF00F2FE),
                isDark: isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStyleCard({
    required String title,
    required String sub,
    required String icon,
    required CertificateStyle style,
    required Color accentColor,
    required bool isDark,
    double? width,
  }) {
    final isSel = _selectedStyle == style;
    return InkWell(
      onTap: () => _onStyleCardSelected(style),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSel
              ? accentColor.withValues(alpha: 0.16)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel ? accentColor : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            width: isSel ? 2 : 1,
          ),
          boxShadow: isSel
              ? [BoxShadow(color: accentColor.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                color: isSel ? accentColor : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            Text(
              sub,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 8,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateCanvas(CertificateStudentData? student) {
    switch (_selectedStyle) {
      case CertificateStyle.royal:
        return _buildRoyalCertificate(student);
      case CertificateStyle.classic:
        return _buildDiplomaticDiplomaCertificate(student);
      case CertificateStyle.natureWood:
        return _buildNatureWoodCertificate(student);
    }
  }

  // =========================================================================
  // 1. STYLE: ROYAL ORNATE GOLD (الملكي الفاخر)
  // Bilingual: Supports Arabic & English natively
  // =========================================================================
  Widget _buildRoyalCertificate(CertificateStudentData? student) {
    const goldColor = Color(0xFFD4AF37);
    const brightGold = Color(0xFFFFD700);

    final scoreText = student?.score ?? '';
    final percentText = student?.percent ?? '';

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 390),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.2,
          colors: [Color(0xFF101935), Color(0xFF060913)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: goldColor, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: goldColor.withValues(alpha: 0.4), width: 1.2),
              ),
            ),
          ),

          // 4 Ornate Corners
          Positioned(top: 6, left: 6, child: _buildCornerOrnament(goldColor, 0)),
          Positioned(top: 6, right: 6, child: _buildCornerOrnament(goldColor, 1)),
          Positioned(bottom: 6, left: 6, child: _buildCornerOrnament(goldColor, 2)),
          Positioned(bottom: 6, right: 6, child: _buildCornerOrnament(goldColor, 3)),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _isEnglish ? 'OFFICIAL COMMENDATION OF EXCELLENCE' : 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: goldColor.withValues(alpha: 0.85),
                    letterSpacing: _isEnglish ? 1.2 : 1.5,
                  ),
                ),
                const SizedBox(height: 6),

                _applyTransform(CertificateElementType.logo, _buildCertificateTopImage(size: 54, borderColor: brightGold)),
                const SizedBox(height: 6),

                Text(
                  _effCenterName,
                  style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                _applyTransform(
                  CertificateElementType.title,
                  InkWell(
                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.title),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        _effCertTitle,
                        textAlign: TextAlign.center,
                        style: _applyTextStyle(
                          CertificateElementType.title,
                          const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: brightGold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 40, height: 1, color: goldColor.withValues(alpha: 0.5)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('❖ ── ✦ ── ❖', style: TextStyle(color: goldColor, fontSize: 10)),
                    ),
                    Container(width: 40, height: 1, color: goldColor.withValues(alpha: 0.5)),
                  ],
                ),
                const SizedBox(height: 6),

                Text(
                  _isEnglish
                      ? 'Proudly and officially presented with highest distinction to:'
                      : 'تَمَّ مَنْحُ هَذَا الوِسَامِ المَلَكِيِّ بِكُلِّ فَخْرٍ وَاعْتِزَازٍ لِلطَّالِبِ المُتَمَيِّزِ:',
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
                const SizedBox(height: 8),

                _applyTransform(
                  CertificateElementType.studentName,
                  InkWell(
                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.studentName),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            goldColor.withValues(alpha: 0.18),
                            goldColor.withValues(alpha: 0.05),
                            goldColor.withValues(alpha: 0.18),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: goldColor.withValues(alpha: 0.45)),
                      ),
                      child: Text(
                        _effStudentName,
                        style: _applyTextStyle(
                          CertificateElementType.studentName,
                          const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: brightGold,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                _applyTransform(
                  CertificateElementType.rankBadge,
                  InkWell(
                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.rankBadge),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), blurRadius: 6),
                        ],
                      ),
                      child: Text(
                        _effRankText,
                        style: _applyTextStyle(
                          CertificateElementType.rankBadge,
                          const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                _applyTransform(
                  CertificateElementType.reason,
                  InkWell(
                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.reason),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        _effReason,
                        style: _applyTextStyle(
                          CertificateElementType.reason,
                          const TextStyle(fontSize: 9.5, color: Colors.white, height: 1.35),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                _applyTransform(
                  CertificateElementType.examScore,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: goldColor.withValues(alpha: 0.25)),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        Text(
                          _isEnglish ? 'Exam: $_effExamTitle' : 'اختبار: $_effExamTitle',
                          style: const TextStyle(fontSize: 9, color: Colors.white70),
                        ),
                        if (_effGroupName.isNotEmpty) ...[
                          const Text('  •  ', style: TextStyle(fontSize: 9, color: goldColor)),
                          Text(
                            _isEnglish ? 'Group: $_effGroupName' : 'مجموعة: $_effGroupName',
                            style: const TextStyle(fontSize: 9, color: Colors.white70),
                          ),
                        ],
                        if (scoreText.isNotEmpty) ...[
                          const Text('  •  ', style: TextStyle(fontSize: 9, color: goldColor)),
                          Text(
                            _isEnglish ? 'Score: $scoreText' : 'الدرجة: $scoreText',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                          ),
                        ],
                        if (percentText.isNotEmpty) ...[
                          const Text('  •  ', style: TextStyle(fontSize: 9, color: goldColor)),
                          Text(
                            _isEnglish ? 'Grade: $percentText' : 'النسبة: $percentText',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: brightGold),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: _applyTransform(
                        CertificateElementType.signatureLeft,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _applyTransform(CertificateElementType.seal, _buildHangingWaxSeal(goldColor)),
                            const SizedBox(width: 8),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _isEnglish ? 'Officially Certified' : 'معتمد رسمياً',
                                    style: const TextStyle(fontSize: 8.5, color: Colors.white54),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  InkWell(
                                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.signatureLeft),
                                    child: Text(
                                      _effDate,
                                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    Flexible(
                      fit: FlexFit.loose,
                      child: _applyTransform(
                        CertificateElementType.signatureRight,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isEnglish ? 'Supervisor & Instructor' : 'معلم المادة والأستاذ المشرف',
                              style: const TextStyle(fontSize: 8.5, color: Colors.white54),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            InkWell(
                              onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.signatureRight),
                              child: Text(
                                '$_effTeacherName ✍️',
                                style: _applyTextStyle(
                                  CertificateElementType.signatureRight,
                                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: brightGold),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              width: 80,
                              height: 1.5,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [goldColor, Colors.transparent]),
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
          ),
        ],
      ),
    );
  }

  Widget _buildCornerOrnament(Color color, int corner) {
    return Transform.rotate(
      angle: corner * 1.5708,
      child: Icon(Icons.all_inclusive_rounded, color: color, size: 14),
    );
  }

  Widget _buildHangingWaxSeal(Color color) {
    return Tooltip(
      message: _isEnglish ? 'Official System Logo • Certified (Tap to edit)' : 'لوجو المنظومة الرسمي • معتمد رسمياً (اضغط للتعديل والتحكم)',
      child: InkWell(
        onTap: _showOfficialLogoOptions,
        onLongPress: () => _showLogoAdjustModal(isBottomSeal: true),
        borderRadius: BorderRadius.circular(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildOfficialLogoImage(size: 40),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 5, height: 9, color: const Color(0xFFDC2626)),
                const SizedBox(width: 2),
                Container(width: 5, height: 9, color: const Color(0xFFDC2626)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 2. STYLE: DIPLOMATIC DIPLOMA (الدبلوم الأكاديمي الرسمي)
  // =========================================================================
  Widget _buildDiplomaticDiplomaCertificate(CertificateStudentData? student) {
    const navyColor = Color(0xFF1E3A8A);
    const darkRed = Color(0xFF991B1B);

    final scoreText = student?.score ?? '50 / 50';
    final percentText = student?.percent ?? '100%';

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 390),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: navyColor, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: darkRed.withValues(alpha: 0.45), width: 1.2),
              ),
            ),
          ),

          Positioned(top: 6, left: 6, child: const Icon(Icons.emergency_rounded, color: darkRed, size: 14)),
          Positioned(top: 6, right: 6, child: const Icon(Icons.emergency_rounded, color: darkRed, size: 14)),
          Positioned(bottom: 6, left: 6, child: const Icon(Icons.emergency_rounded, color: darkRed, size: 14)),
          Positioned(bottom: 6, right: 6, child: const Icon(Icons.emergency_rounded, color: darkRed, size: 14)),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _applyTransform(CertificateElementType.logo, _buildCertificateTopImage(size: 52, borderColor: navyColor)),
                const SizedBox(height: 6),

                Text(
                  _effCenterName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: navyColor),
                ),
                const SizedBox(height: 2),

                _applyTransform(
                  CertificateElementType.title,
                  Text(
                    _effCertTitle,
                    style: _applyTextStyle(
                      CertificateElementType.title,
                      const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: navyColor,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 120,
                  height: 2,
                  color: darkRed,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                ),

                Text(
                  _isEnglish
                      ? 'This is to certify that the distinguished student:'
                      : 'تَشْهَدُ إِدَارَةُ المَرْكَزِ وَلَجْنَةُ التَّقْيِيمِ بِأَنَّ الطَّالِبَ النَّجِيبَ:',
                  style: const TextStyle(fontSize: 9.5, color: Colors.black87),
                ),
                const SizedBox(height: 4),

                _applyTransform(
                  CertificateElementType.studentName,
                  Text(
                    _effStudentName,
                    style: _applyTextStyle(
                      CertificateElementType.studentName,
                      const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: darkRed,
                        decoration: TextDecoration.underline,
                        decorationColor: darkRed,
                        decorationThickness: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                Text(
                  _isEnglish
                      ? 'Has successfully accomplished all academic requirements for the examination:'
                      : 'قَدْ أَتَمَّ بِنَجَاحٍ وَاقْتِدَارٍ اسْتِحْقَاقَ اخْتِبَارِ:',
                  style: const TextStyle(fontSize: 9, color: Colors.black87),
                ),
                const SizedBox(height: 2),

                Text(
                  _effGroupName.isNotEmpty ? '« $_effExamTitle » • $_effGroupName' : '« $_effExamTitle »',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: navyColor),
                ),
                const SizedBox(height: 4),

                _applyTransform(
                  CertificateElementType.reason,
                  Text(
                    _isEnglish
                        ? 'And achieved $_effRankText with a score of ($scoreText) and ($percentText) with High Distinction.\nIn recognition whereof, this official diploma is proudly granted.'
                        : 'وَحَصَلَ عَلَى $_effRankText بِمَجْمُوعِ ($scoreText) وَنِسْبَةِ ($percentText) بِمَرْتَبَةِ الشَّرَفِ.\nوَبِنَاءً عَلَيْهِ مُنِحَ هَذِهِ الشَّهَادَةَ اعْتِرَافاً بِتَفَوُّقِهِ وَتَقْدِيراً لِعِلْمِهِ.',
                    textAlign: TextAlign.center,
                    style: _applyTextStyle(
                      CertificateElementType.reason,
                      const TextStyle(fontSize: 9, color: Colors.black87, height: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: _applyTransform(
                        CertificateElementType.signatureLeft,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _applyTransform(CertificateElementType.seal, _buildHangingWaxSeal(darkRed)),
                            const SizedBox(width: 8),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _isEnglish ? 'Officially Certified' : 'معتمد رسمياً',
                                    style: const TextStyle(fontSize: 8, color: Colors.black54),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _effDate,
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    Flexible(
                      fit: FlexFit.loose,
                      child: _applyTransform(
                        CertificateElementType.signatureRight,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isEnglish ? 'Course Supervisor' : 'توقيع أستاذ المادة',
                              style: const TextStyle(fontSize: 8, color: Colors.black54),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_effTeacherName ✍️',
                              style: _applyTextStyle(
                                CertificateElementType.signatureRight,
                                const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: navyColor),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Container(width: 70, height: 1, color: navyColor.withValues(alpha: 0.5)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. STYLE: NATURE WOOD & BOTANICAL LAUREL (الخشبي المستوحى من الطبيعة)
  // Bilingual: Arabic & English with rich organic textures and laurel wreaths
  // =========================================================================
  Widget _buildNatureWoodCertificate(CertificateStudentData? student) {
    const woodBorder = Color(0xFFC49726);
    const brightAmber = Color(0xFFFFD700);
    const warmCream = Color(0xFFFCE7CF);
    const leafGreen = Color(0xFF4ADE80);

    final scoreText = student?.score ?? '50 / 50';
    final percentText = student?.percent ?? '100%';

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 460),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.3,
          colors: [Color(0xFF2E190E), Color(0xFF140B06)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: woodBorder, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.75),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Inner Dashed Warm Gold Border
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: woodBorder.withValues(alpha: 0.45), width: 1.2),
              ),
            ),
          ),

          // 4 Antique Brass Corner Bolts
          Positioned(top: 6, left: 6, child: _buildCornerBrassBolt()),
          Positioned(top: 6, right: 6, child: _buildCornerBrassBolt()),
          Positioned(bottom: 6, left: 6, child: _buildCornerBrassBolt()),
          Positioned(bottom: 6, right: 6, child: _buildCornerBrassBolt()),

          // 4 Botanical Corner Foliage
          Positioned(top: 10, left: 10, child: _buildBotanicalFoliage(0)),
          Positioned(top: 10, right: 10, child: _buildBotanicalFoliage(1)),
          Positioned(bottom: 10, right: 10, child: _buildBotanicalFoliage(2)),
          Positioned(bottom: 10, left: 10, child: _buildBotanicalFoliage(3)),

          // Watermark in Background
          Positioned.fill(
            child: Center(
              child: Icon(
                Icons.park_rounded,
                size: 160,
                color: Colors.white.withValues(alpha: 0.03),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Logo
                _applyTransform(
                  CertificateElementType.logo,
                  _buildCertificateTopImage(size: 44, borderColor: woodBorder),
                ),
                const SizedBox(height: 4),

                // Institution Name (Bilingual)
                Text(
                  _effCenterName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: warmCream,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  _isEnglish ? 'ACADEMY OF EXCELLENCE • EST. 2026' : 'صَرْحُ الرِّيَادَةِ وَالتَّمَيُّزِ الأَكَادِيمِيِّ المَعْتَمَد',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: woodBorder.withValues(alpha: 0.9),
                    letterSpacing: _isEnglish ? 1.5 : 0.5,
                  ),
                ),
                const SizedBox(height: 6),

                // Bismillah / Header Motto
                Text(
                  _isEnglish ? 'OFFICIAL COMMENDATION OF HIGHEST HONORS' : 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: woodBorder.withValues(alpha: 0.9),
                    letterSpacing: _isEnglish ? 1.5 : 1.2,
                  ),
                ),
                const SizedBox(height: 2),

                // Main Title (Bilingual)
                _applyTransform(
                  CertificateElementType.title,
                  InkWell(
                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.title),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _effCertTitle,
                            textAlign: TextAlign.center,
                            style: _applyTextStyle(
                              CertificateElementType.title,
                              const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: brightAmber,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Text(
                            'CERTIFICATE OF MERIT & HIGHEST HONORS',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: woodBorder.withValues(alpha: 0.85),
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 4),
                Text(
                  _isEnglish
                      ? 'The Academic Board & Faculty proudly confer this prestigious award upon:'
                      : 'يَسُرُّ مَجْلِسَ الإِدَارَةِ وَهَيْئَةَ التَّدْرِيسِ مَنْحُ هَذَا الوِسَامِ الرَّفِيعِ إِلَى الطَّالِبِ المَتَمَيِّزِ:',
                  style: TextStyle(
                    fontSize: 9,
                    color: warmCream.withValues(alpha: 0.85),
                    fontStyle: _isEnglish ? FontStyle.italic : FontStyle.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),

                // Student Name - Engraved Brass Plaque
                _applyTransform(
                  CertificateElementType.studentName,
                  InkWell(
                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.studentName),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD97706), Color(0xFFFEF3C7), Color(0xFFB45309)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF451A03), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _effStudentName,
                            style: _applyTextStyle(
                              CertificateElementType.studentName,
                              const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF270E02),
                              ),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'VALEDICTORIAN CANDIDATE',
                            style: TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF451A03).withValues(alpha: 0.8),
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Valedictorian Laurel Wreath Badge
                _applyTransform(
                  CertificateElementType.rankBadge,
                  InkWell(
                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.rankBadge),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1008),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: woodBorder, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🌿', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            _effRankText,
                            style: _applyTextStyle(
                              CertificateElementType.rankBadge,
                              const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: brightAmber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('👑', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Nature-Inspired Citation
                _applyTransform(
                  CertificateElementType.reason,
                  InkWell(
                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.reason),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        _effReason,
                        style: _applyTextStyle(
                          CertificateElementType.reason,
                          TextStyle(
                            fontSize: 9.5,
                            color: warmCream.withValues(alpha: 0.95),
                            height: 1.4,
                          ),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Organic Performance Slats
                _applyTransform(
                  CertificateElementType.examScore,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF140A05).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: woodBorder.withValues(alpha: 0.3)),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text(
                          _isEnglish ? 'Subject: $_effExamTitle' : 'المادة: $_effExamTitle',
                          style: TextStyle(fontSize: 9, color: warmCream.withValues(alpha: 0.8)),
                        ),
                        if (_effGroupName.isNotEmpty) ...[
                          const Text(' • ', style: TextStyle(fontSize: 9, color: woodBorder)),
                          Text(
                            _isEnglish ? 'Group: $_effGroupName' : 'مجموعة: $_effGroupName',
                            style: TextStyle(fontSize: 9, color: warmCream.withValues(alpha: 0.8)),
                          ),
                        ],
                        if (scoreText.isNotEmpty) ...[
                          const Text(' • ', style: TextStyle(fontSize: 9, color: woodBorder)),
                          Text(
                            _isEnglish ? 'Score: $scoreText' : 'الدرجة: $scoreText',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: leafGreen),
                          ),
                        ],
                        if (percentText.isNotEmpty) ...[
                          const Text(' • ', style: TextStyle(fontSize: 9, color: woodBorder)),
                          Text(
                            _isEnglish ? 'Grade: $percentText' : 'النسبة: $percentText',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: brightAmber),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Footer (Signatures & Seal)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: _applyTransform(
                        CertificateElementType.signatureLeft,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _applyTransform(
                              CertificateElementType.seal,
                              _buildHangingWaxSeal(woodBorder),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _isEnglish ? 'Officially Certified' : 'معتمد رسمياً',
                                    style: TextStyle(fontSize: 8, color: warmCream.withValues(alpha: 0.6)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  InkWell(
                                    onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.signatureLeft),
                                    child: Text(
                                      _effDate,
                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    Flexible(
                      fit: FlexFit.loose,
                      child: _applyTransform(
                        CertificateElementType.signatureRight,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isEnglish ? 'Department Supervisor' : 'معلم المادة ورئيس القسم',
                              style: TextStyle(fontSize: 8, color: warmCream.withValues(alpha: 0.6)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            InkWell(
                              onTap: () => _showTextAndFontEditor(initialType: CertificateElementType.signatureRight),
                              child: Text(
                                '$_effTeacherName ✍️',
                                style: _applyTextStyle(
                                  CertificateElementType.signatureRight,
                                  const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: brightAmber),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              width: 75,
                              height: 1.5,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(colors: [woodBorder, Colors.transparent]),
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
          ),
        ],
      ),
    );
  }

  Widget _buildCornerBrassBolt() {
    return Container(
      width: 12,
      height: 12,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFFEF3C7), Color(0xFFD97706), Color(0xFF451A03)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.add, size: 8, color: Color(0xFF270E02)),
      ),
    );
  }

  Widget _buildBotanicalFoliage(int corner) {
    return Transform.rotate(
      angle: corner * 1.5708,
      child: const Icon(
        Icons.eco_rounded,
        color: Color(0xFFD4AF37),
        size: 13,
      ),
    );
  }
}
