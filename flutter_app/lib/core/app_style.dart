import 'package:flutter/material.dart';

/// Design tokens and glassmorphism styles matching the Dark Glassmorphism specification
class AppStyle {
  // Brand Backgrounds
  static const Color darkBgScaffold = Color(0xFF071022);
  static const Color darkBgCard = Color(0xFF0E1E38);
  static const Color darkBgCardAlt = Color(0xFF132747);
  static const Color darkBorder = Color(0xFF24426D);
  static const Color darkBorderGlow = Color(0xFF2A4B7C);

  // Gradients for Cards
  static const LinearGradient darkScaffoldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0C1C38),
      Color(0xFF09152B),
      Color(0xFF071124),
    ],
  );

  static const LinearGradient heroCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xF2173158),
      Color(0xF2122646),
      Color(0xF20F203C),
    ],
  );

  static const LinearGradient studentsKpiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xE6163461),
      Color(0xF2112648),
      Color(0xF20D1D38),
    ],
  );

  static const LinearGradient attendanceKpiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xE610383A),
      Color(0xF20E2638),
      Color(0xF20C1D33),
    ],
  );

  static const LinearGradient revenueKpiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xE6103B38),
      Color(0xF210273B),
      Color(0xF20C1D34),
    ],
  );

  static const LinearGradient overdueKpiGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xE6471932),
      Color(0xF22A1936),
      Color(0xF2141D35),
    ],
  );

  static const LinearGradient summaryCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xF2152C4E),
      Color(0xF2112340),
      Color(0xF20E1C36),
    ],
  );

  static const LinearGradient primaryButtonGradient = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [
      Color(0xFF0EA5E9),
      Color(0xFF0284C7),
      Color(0xFF2563EB),
    ],
  );

  static const LinearGradient emeraldProgressGradient = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [
      Color(0xFF10B981),
      Color(0xFF34D399),
      Color(0xFF86EFAC),
    ],
  );

  static const LinearGradient skyIconGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF38BDF8), Color(0xFF2563EB)],
  );

  static const LinearGradient emeraldIconGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34D399), Color(0xFF059669)],
  );

  static const LinearGradient roseIconGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFB7185), Color(0xFFBE123C)],
  );

  static const LinearGradient purpleIconGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA855F7), Color(0xFF6366F1)],
  );

  // Box Decorations
  static BoxDecoration glassCardDecoration({
    required bool isDark,
    LinearGradient? gradient,
    Color? borderColor,
    double borderRadius = 22,
  }) {
    if (!isDark) {
      return BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      );
    }

    return BoxDecoration(
      gradient: gradient ?? summaryCardGradient,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? darkBorder,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
