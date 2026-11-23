import 'dart:convert';
import 'package:flutter/material.dart';

enum CertificateStyle {
  royal, // 1. الذهبي الملكي الفاخر 👑
  classic, // 2. الدبلوم الأكاديمي الرسمي 🏛️
  natureWood, // 3. الخشبي المستوحى من الطبيعة 🌿🪵
}

enum RankTier {
  rank1, // 🥇 المركز الأول
  rank2, // 🥈 المركز الثاني
  rank3, // 🥉 المركز الثالث
  ranks4to10, // 🎖️ المراكز (4 - 10) الشهادة الموحدة
}

enum CertificateElementType {
  title, // عنوان الشهادة الرئيسي
  studentName, // اسم الطالب المكرم
  rankBadge, // الرتبة والوسام
  reason, // نص التقدير والإشادة
  examScore, // بيانات الاختبار والدرجة
  signatureLeft, // توقيع السنتر / التاريخ
  signatureRight, // توقيع المعلم المشرف
  logo, // شعار المنظومة الرسمي
  seal, // الختم الشمعي / وسام التتويج
}

extension CertificateElementTypeExt on CertificateElementType {
  String get displayNameAr {
    switch (this) {
      case CertificateElementType.title:
        return 'عنوان الشهادة';
      case CertificateElementType.studentName:
        return 'اسم الطالب المكرم';
      case CertificateElementType.rankBadge:
        return 'الرتبة والوسام';
      case CertificateElementType.reason:
        return 'نص التقدير والإشادة';
      case CertificateElementType.examScore:
        return 'بيانات الاختبار والدرجة';
      case CertificateElementType.signatureLeft:
        return 'توقيع السنتر / التاريخ';
      case CertificateElementType.signatureRight:
        return 'توقيع المعلم المشرف';
      case CertificateElementType.logo:
        return 'شعار المنظومة';
      case CertificateElementType.seal:
        return 'الختم الشمعي / الوسام';
    }
  }

  String get displayNameEn {
    switch (this) {
      case CertificateElementType.title:
        return 'Certificate Title';
      case CertificateElementType.studentName:
        return 'Student Name';
      case CertificateElementType.rankBadge:
        return 'Rank & Badge';
      case CertificateElementType.reason:
        return 'Commendation Text';
      case CertificateElementType.examScore:
        return 'Exam & Score';
      case CertificateElementType.signatureLeft:
        return 'Center / Date Block';
      case CertificateElementType.signatureRight:
        return 'Teacher Signature';
      case CertificateElementType.logo:
        return 'System Logo';
      case CertificateElementType.seal:
        return 'Wax Seal / Crest';
    }
  }

  String get iconStr {
    switch (this) {
      case CertificateElementType.title:
        return '🏷️';
      case CertificateElementType.studentName:
        return '👤';
      case CertificateElementType.rankBadge:
        return '🎖️';
      case CertificateElementType.reason:
        return '✍️';
      case CertificateElementType.examScore:
        return '📝';
      case CertificateElementType.signatureLeft:
        return '🏛️';
      case CertificateElementType.signatureRight:
        return '👨‍🏫';
      case CertificateElementType.logo:
        return '🏫';
      case CertificateElementType.seal:
        return '🏵️';
    }
  }

  bool get isTextElement {
    switch (this) {
      case CertificateElementType.logo:
      case CertificateElementType.seal:
        return false;
      default:
        return true;
    }
  }
}

class CertificateElementConfig {
  double dx; // Horizontal offset in pixels (-150 to +150)
  double dy; // Vertical offset in pixels (-150 to +150)
  double scale; // Size multiplier (0.3 to 3.0)
  double fontSize; // Font size in pt (8 to 44)
  String fontFamily; // Font family ('Cairo', 'Amiri', 'Tajawal', 'serif', 'sans-serif')
  int fontWeightIndex; // 0: w300, 1: w400, 2: w500, 3: w600, 4: w700, 5: w900
  bool isItalic;
  bool isUnderline;
  double letterSpacing; // Letter spacing (-2.0 to 10.0)
  double rotation; // Rotation in degrees (-45 to 45)
  int colorValue; // ARGB integer
  bool hasShadow; // Text shadow / glow
  int shadowColorValue; // Shadow ARGB
  double shadowBlur; // Shadow blur radius
  bool isVisible;
  String? customText; // In-place text override

  CertificateElementConfig({
    this.dx = 0.0,
    this.dy = 0.0,
    this.scale = 1.0,
    this.fontSize = 16.0,
    this.fontFamily = 'Cairo',
    this.fontWeightIndex = 4,
    this.isItalic = false,
    this.isUnderline = false,
    this.letterSpacing = 0.0,
    this.rotation = 0.0,
    this.colorValue = 0xFFFFD700,
    this.hasShadow = false,
    this.shadowColorValue = 0x88000000,
    this.shadowBlur = 4.0,
    this.isVisible = true,
    this.customText,
  });

  FontWeight get fontWeight {
    switch (fontWeightIndex) {
      case 0:
        return FontWeight.w300;
      case 1:
        return FontWeight.w400;
      case 2:
        return FontWeight.w500;
      case 3:
        return FontWeight.w600;
      case 4:
        return FontWeight.w700;
      case 5:
        return FontWeight.w900;
      default:
        return FontWeight.w700;
    }
  }

  Color get color => Color(colorValue);
  Color get shadowColor => Color(shadowColorValue);

  List<Shadow>? get shadows {
    if (!hasShadow) return null;
    return [
      Shadow(
        color: shadowColor,
        offset: const Offset(1.5, 1.5),
        blurRadius: shadowBlur,
      ),
    ];
  }

  CertificateElementConfig copyWith({
    double? dx,
    double? dy,
    double? scale,
    double? fontSize,
    String? fontFamily,
    int? fontWeightIndex,
    bool? isItalic,
    bool? isUnderline,
    double? letterSpacing,
    double? rotation,
    int? colorValue,
    bool? hasShadow,
    int? shadowColorValue,
    double? shadowBlur,
    bool? isVisible,
    String? customText,
  }) {
    return CertificateElementConfig(
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
      scale: scale ?? this.scale,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeightIndex: fontWeightIndex ?? this.fontWeightIndex,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      rotation: rotation ?? this.rotation,
      colorValue: colorValue ?? this.colorValue,
      hasShadow: hasShadow ?? this.hasShadow,
      shadowColorValue: shadowColorValue ?? this.shadowColorValue,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      isVisible: isVisible ?? this.isVisible,
      customText: customText ?? this.customText,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dx': dx,
      'dy': dy,
      'scale': scale,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'fontWeightIndex': fontWeightIndex,
      'isItalic': isItalic,
      'isUnderline': isUnderline,
      'letterSpacing': letterSpacing,
      'rotation': rotation,
      'colorValue': colorValue,
      'hasShadow': hasShadow,
      'shadowColorValue': shadowColorValue,
      'shadowBlur': shadowBlur,
      'isVisible': isVisible,
      if (customText != null) 'customText': customText,
    };
  }

  factory CertificateElementConfig.fromMap(Map<String, dynamic> map) {
    return CertificateElementConfig(
      dx: (map['dx'] as num?)?.toDouble() ?? 0.0,
      dy: (map['dy'] as num?)?.toDouble() ?? 0.0,
      scale: (map['scale'] as num?)?.toDouble() ?? 1.0,
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 16.0,
      fontFamily: (map['fontFamily'] as String?) ?? 'Cairo',
      fontWeightIndex: (map['fontWeightIndex'] as int?) ?? 4,
      isItalic: (map['isItalic'] as bool?) ?? false,
      isUnderline: (map['isUnderline'] as bool?) ?? false,
      letterSpacing: (map['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      rotation: (map['rotation'] as num?)?.toDouble() ?? 0.0,
      colorValue: (map['colorValue'] as int?) ?? 0xFFFFD700,
      hasShadow: (map['hasShadow'] as bool?) ?? false,
      shadowColorValue: (map['shadowColorValue'] as int?) ?? 0x88000000,
      shadowBlur: (map['shadowBlur'] as num?)?.toDouble() ?? 4.0,
      isVisible: (map['isVisible'] as bool?) ?? true,
      customText: map['customText'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory CertificateElementConfig.fromJson(String source) =>
      CertificateElementConfig.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class CertificateTierLayout {
  final Map<CertificateElementType, CertificateElementConfig> elements;

  CertificateTierLayout({required this.elements});

  CertificateElementConfig getConfig(CertificateElementType type) {
    return elements[type] ?? CertificateElementConfig();
  }

  void setConfig(CertificateElementType type, CertificateElementConfig config) {
    elements[type] = config;
  }

  /// Generate intelligent baseline layout configurations for each style
  factory CertificateTierLayout.defaultsFor(String styleName) {
    final Map<CertificateElementType, CertificateElementConfig> map = {};

    switch (styleName) {
      case 'royal':
        map[CertificateElementType.title] = CertificateElementConfig(
          fontSize: 19.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 5,
          colorValue: 0xFFFFD700,
        );
        map[CertificateElementType.studentName] = CertificateElementConfig(
          fontSize: 19.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 5,
          colorValue: 0xFFFFD700,
        );
        map[CertificateElementType.rankBadge] = CertificateElementConfig(
          fontSize: 10.5,
          fontFamily: 'Cairo',
          fontWeightIndex: 5,
          colorValue: 0xFF000000,
        );
        map[CertificateElementType.reason] = CertificateElementConfig(
          fontSize: 9.5,
          fontFamily: 'Cairo',
          fontWeightIndex: 2,
          colorValue: 0xFFFFFFFF,
        );
        map[CertificateElementType.examScore] = CertificateElementConfig(
          fontSize: 9.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 4,
          colorValue: 0xFF34D399,
        );
        map[CertificateElementType.signatureLeft] = CertificateElementConfig(
          fontSize: 9.5,
          fontFamily: 'Cairo',
          fontWeightIndex: 4,
          colorValue: 0xFFD4AF37,
        );
        map[CertificateElementType.signatureRight] = CertificateElementConfig(
          fontSize: 9.5,
          fontFamily: 'Cairo',
          fontWeightIndex: 4,
          colorValue: 0xFFD4AF37,
        );
        map[CertificateElementType.logo] = CertificateElementConfig(scale: 1.0);
        map[CertificateElementType.seal] = CertificateElementConfig(scale: 1.0);
        break;

      case 'classic':
      default:
        map[CertificateElementType.title] = CertificateElementConfig(
          fontSize: 19.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 5,
          colorValue: 0xFF1E3A8A,
        );
        map[CertificateElementType.studentName] = CertificateElementConfig(
          fontSize: 19.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 5,
          colorValue: 0xFF1E3A8A,
        );
        map[CertificateElementType.rankBadge] = CertificateElementConfig(
          fontSize: 10.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 5,
          colorValue: 0xFFB45309,
        );
        map[CertificateElementType.reason] = CertificateElementConfig(
          fontSize: 9.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 2,
          colorValue: 0xFF334155,
        );
        map[CertificateElementType.examScore] = CertificateElementConfig(
          fontSize: 9.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 4,
          colorValue: 0xFF1E3A8A,
        );
        map[CertificateElementType.signatureLeft] = CertificateElementConfig(
          fontSize: 9.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 4,
          colorValue: 0xFF1E3A8A,
        );
        map[CertificateElementType.signatureRight] = CertificateElementConfig(
          fontSize: 9.0,
          fontFamily: 'Cairo',
          fontWeightIndex: 4,
          colorValue: 0xFF1E3A8A,
        );
        map[CertificateElementType.logo] = CertificateElementConfig(scale: 1.0);
        map[CertificateElementType.seal] = CertificateElementConfig(scale: 1.0);
        break;
    }

    return CertificateTierLayout(elements: map);
  }

  Map<String, dynamic> toMap() {
    return elements.map((key, value) => MapEntry(key.name, value.toMap()));
  }

  factory CertificateTierLayout.fromMap(Map<String, dynamic> map, String styleName) {
    final defaults = CertificateTierLayout.defaultsFor(styleName);
    final result = Map<CertificateElementType, CertificateElementConfig>.from(defaults.elements);
    map.forEach((k, v) {
      final type = CertificateElementType.values.where((e) => e.name == k).firstOrNull;
      if (type != null && v is Map<String, dynamic>) {
        result[type] = CertificateElementConfig.fromMap(v);
      }
    });
    return CertificateTierLayout(elements: result);
  }

  String toJson() => jsonEncode(toMap());

  factory CertificateTierLayout.fromJson(String source, String styleName) {
    try {
      final map = jsonDecode(source) as Map<String, dynamic>;
      return CertificateTierLayout.fromMap(map, styleName);
    } catch (_) {
      return CertificateTierLayout.defaultsFor(styleName);
    }
  }

  factory CertificateTierLayout.defaultFor(RankTier tier, CertificateStyle style) {
    return CertificateTierLayout.defaultsFor(style.name);
  }

  factory CertificateTierLayout.fromJsonString(RankTier tier, CertificateStyle style, String source) {
    return CertificateTierLayout.fromJson(source, style.name);
  }
}
